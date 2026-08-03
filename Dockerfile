# =============================================================================
# SpecCompiler — the single distribution image.
#
# Built on Ubuntu 24.04: the same stock apt pandoc + compiled Lua C extensions
# the native install uses (scripts/install-native.sh), plus the optional
# renderers — deno (model-owned charts), JRE + PlantUML + graphviz (puml
# floats), python + reqif (ReqIF interop). One published tag:
#
#   ghcr.io/specir/speccompiler:latest
#
# Local build:  docker build -t speccompiler-core:latest .
# Versions are pinned in scripts/versions.env.
# =============================================================================

# --- build stage: compile the four Lua C extensions, fetch pinned tools ------
FROM ubuntu:24.04 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake pkg-config git curl unzip ca-certificates \
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
# installer after accepting Microsoft's core-font EULA.
RUN apt-get update \
    && echo 'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' \
       | debconf-set-selections \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    pandoc \
    liblua5.4-0 libsqlite3-0 libzip4t64 \
    python3 python3-uno libreoffice-writer libreoffice-math poppler-utils \
    default-jre-headless graphviz fonts-dejavu-core \
    fontconfig ttf-mscorefonts-installer \
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
