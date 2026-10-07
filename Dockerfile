# =============================================================================
# SpecCompiler — the single distribution image.
#
# Built on Ubuntu 24.04: the same stock apt pandoc + compiled Lua C extensions
# the native install uses (scripts/install-native.sh), plus the optional
# renderers — deno (model-owned charts), JRE + PlantUML + graphviz (puml
# floats), Node + mermaid-cli (mermaid floats), python + reqif (ReqIF
# interop). One published tag:
#
#   ghcr.io/specir/speccompiler:latest
#
# Local build:  docker build -t speccompiler-core:latest .
# Versions are pinned in scripts/versions.env.
# =============================================================================

# --- build stage: compile the four Lua C extensions, fetch pinned tools ------
FROM ubuntu:24.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git curl unzip xz-utils ca-certificates \
    liblua5.4-dev libsqlite3-dev libzip-dev peg \
    python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/speccompiler

COPY scripts/build-extensions.sh scripts/versions.env ./scripts/
COPY src/tools/ ./src/tools/
RUN bash scripts/build-extensions.sh /opt/speccompiler/vendor

# deno (official glibc binary) + plantuml.jar, pinned via versions.env
RUN . ./scripts/versions.env \
    && case "$(uname -m)" in \
         x86_64)  DENO_ARCH=x86_64-unknown-linux-gnu ;; \
         aarch64) DENO_ARCH=aarch64-unknown-linux-gnu ;; \
         *) echo "unsupported arch: $(uname -m)" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-${DENO_ARCH}.zip" -o /tmp/deno.zip \
    && unzip -q /tmp/deno.zip -d /usr/local/bin && rm /tmp/deno.zip \
    && curl -fsSL "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar" \
         -o /opt/speccompiler/vendor/plantuml.jar

# node + mermaid-cli (mmdc) for mermaid floats. Puppeteer downloads its Chrome
# into vendor/puppeteer at install time, so the runtime stage gets node, the
# CLI and the browser with the rest of vendor/.
RUN . ./scripts/versions.env \
    && case "$(uname -m)" in \
         x86_64)  NODE_ARCH=x64 ;; \
         aarch64) NODE_ARCH=arm64 ;; \
         *) echo "unsupported arch: $(uname -m)" && exit 1 ;; \
       esac \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz \
    && mkdir -p /opt/speccompiler/vendor/node \
    && tar -xJf /tmp/node.tar.xz -C /opt/speccompiler/vendor/node --strip-components=1 \
    && rm /tmp/node.tar.xz \
    && PATH="/opt/speccompiler/vendor/node/bin:$PATH" \
       PUPPETEER_CACHE_DIR=/opt/speccompiler/vendor/puppeteer \
       npm install -g --prefix /opt/speccompiler/vendor/mermaid \
            "@mermaid-js/mermaid-cli@${MERMAID_CLI_VERSION}" "puppeteer@${PUPPETEER_VERSION}" \
    && rm -rf /root/.npm

# reqif (fork with the specir subpackage) for `python3 -m reqif.specir`
RUN python3 -m pip install --break-system-packages --no-cache-dir \
      --target=/opt/speccompiler/vendor/python \
      "git+https://github.com/crisclacerda/reqif.git@main"

# --- runtime stage -----------------------------------------------------------
FROM ubuntu:24.04
LABEL org.opencontainers.image.source="https://github.com/SpecIR/SpecCompiler" \
      org.opencontainers.image.description="SpecCompiler - extensible type system for Markdown" \
      org.opencontainers.image.licenses="MIT"

# stock pandoc (links shared liblua5.4) + runtime libs for the extensions
# + LibreOffice for DOCX field/PDF finalization + Microsoft core fonts used by
# the official ABNT/USP templates. The fonts are downloaded by Ubuntu's
# installer after accepting Microsoft's core-font EULA. The libnss3..libxshmfence1
# group is what puppeteer's Chrome (mermaid-cli) needs at runtime.
RUN apt-get update \
    && echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' \
       | debconf-set-selections \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    pandoc \
    liblua5.4-0 libsqlite3-0 libzip4t64 \
    python3 python3-uno libreoffice-writer libreoffice-math poppler-utils \
    default-jre-headless graphviz fonts-dejavu-core \
    fontconfig ttf-mscorefonts-installer \
    libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libgbm1 \
    libasound2t64 libgtk-3-0t64 libxshmfence1 \
    zip unzip ca-certificates \
    && fc-cache -f \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/speccompiler

COPY --from=build /opt/speccompiler/vendor/ ./vendor/
COPY --from=build /usr/local/bin/deno /usr/local/bin/deno
COPY src/ ./src/
COPY models/default/ ./models/default/
COPY models/sw_docs/ ./models/sw_docs/
# tests/ ships too so model-overlay images (e.g. specc-abnt) can run their
# model suite via /opt/speccompiler/tests/run.sh <model>-tests
COPY tests/ ./tests/
# guard: the core must stay Deno-free (charts are model-owned)
RUN ! grep -rq "deno" src/ models/default/ || (echo "core references deno" && exit 1)

# `plantuml` on PATH for the puml float
RUN printf '#!/bin/sh\nexec java -jar /opt/speccompiler/vendor/plantuml.jar "$@"\n' \
      > /usr/local/bin/plantuml && chmod +x /usr/local/bin/plantuml

# `mmdc` on PATH for the mermaid float. The image runs as root, where Chrome
# refuses to start its sandbox, so the wrapper always passes a puppeteer
# config that disables it.
RUN printf '{"args":["--no-sandbox","--disable-gpu","--disable-dev-shm-usage"]}\n' \
      > /opt/speccompiler/vendor/puppeteer-config.json \
    && printf '#!/bin/sh\nexport PATH="/opt/speccompiler/vendor/node/bin:$PATH" PUPPETEER_CACHE_DIR=/opt/speccompiler/vendor/puppeteer\nexec /opt/speccompiler/vendor/mermaid/bin/mmdc -p /opt/speccompiler/vendor/puppeteer-config.json "$@"\n' \
      > /usr/local/bin/mmdc && chmod +x /usr/local/bin/mmdc

# the same unified wrapper the native install uses, running in native mode
COPY scripts/specc /usr/local/bin/specc
RUN chmod +x /usr/local/bin/specc

ENV SPECC_MODE=native \
    SPECCOMPILER_HOME=/opt/speccompiler \
    SPECCOMPILER_DIST=/opt/speccompiler \
    PYTHONPATH=/opt/speccompiler/vendor/python \
    DENO_DIR=/opt/speccompiler/vendor/deno_cache \
    DENO_NO_UPDATE_CHECK=1 \
    LANG=C.UTF-8 \
    LUA_PATH="/opt/speccompiler/src/?.lua;/opt/speccompiler/src/?/init.lua;/opt/speccompiler/?.lua;/opt/speccompiler/?/init.lua;/opt/speccompiler/vendor/?.lua;/opt/speccompiler/vendor/?/init.lua;/opt/speccompiler/vendor/slaxml/?.lua;;" \
    LUA_CPATH="/opt/speccompiler/vendor/?.so;/opt/speccompiler/vendor/?/?.so;;"

WORKDIR /workspace
ENTRYPOINT ["specc"]
