# Lean SpecCompiler image — a thin overlay on the OFFICIAL pandoc image.
#
# Core engine = stock pandoc (which links a shared liblua5.4) + our four C
# extensions compiled for THIS image's libc (musl) against the image's system
# Lua + our Lua source. No GHC, no vendored pandoc, no vendored Lua.
#
# Stages:
#   lean (default) — core only: stock pandoc + extensions + Lua source.
#                    Deno/charts and Java/PlantUML are intentionally absent.
#   full           — lean + the optional external renderer binaries (deno,
#                    plantuml+graphviz). This is what CI tests and publishes;
#                    deno serves model-owned chart capabilities (e.g. abnt),
#                    plantuml serves the default model's PLANTUML float.
#
# Build:  docker build -f Dockerfile.lean -t speccompiler:lean .
#         docker build -f Dockerfile.lean --target full -t speccompiler:latest .
# Pinned: suite goldens verified green on pandoc 3.8.3 (pandoc/core:3.9 drifts
# on HTML output; 3.6's Alpine ships deno 2.0.6, too old for the chart
# renderer's npm-compat shims).
ARG PANDOC_TAG=3.8
FROM pandoc/core:${PANDOC_TAG} AS lean

# musl toolchain + system Lua 5.4 / SQLite / libuv / libzip
# (peg/leg for luaamath isn't packaged on Alpine — build-extensions.sh builds it from source)
RUN apk add --no-cache bash build-base cmake git curl unzip zip \
      lua5.4-dev sqlite-dev libuv-dev libzip-dev

WORKDIR /opt/speccompiler

# 1) compile the four C extensions for musl against the image's system Lua
COPY scripts/build-extensions.sh scripts/versions.env ./scripts/
COPY src/tools/ ./src/tools/
RUN bash scripts/build-extensions.sh /opt/speccompiler/vendor

# 2) application code + core models (charts/abnt are out of the lean core)
#    tests/ ships too so model-overlay images (e.g. specc-abnt) can run their
#    model suite via /opt/speccompiler/tests/run.sh <model>-tests
COPY src/ ./src/
COPY models/default/ ./models/default/
COPY models/sw_docs/ ./models/sw_docs/
COPY tests/ ./tests/
# guard: the lean core must stay Deno-free (charts are model-owned)
RUN ! grep -rq "deno" src/ models/default/ || (echo "lean core references deno" && exit 1)

# 3) runtime env: stock pandoc (already on PATH) + our vendor + src
ENV SPECCOMPILER_HOME=/opt/speccompiler \
    SPECCOMPILER_DIST=/opt/speccompiler \
    LUA_PATH="/opt/speccompiler/src/?.lua;/opt/speccompiler/src/?/init.lua;/opt/speccompiler/?.lua;/opt/speccompiler/?/init.lua;/opt/speccompiler/vendor/?.lua;/opt/speccompiler/vendor/slaxml/?.lua;;" \
    LUA_CPATH="/opt/speccompiler/vendor/?.so;/opt/speccompiler/vendor/?/?.so;;"

# `specc build project.yaml` -> stock pandoc + our filter
RUN printf '#!/bin/sh\nset -e\n[ "$1" = build ] && shift\nP="${1:-project.yaml}"\ncd "$(dirname "$P")"\nexec pandoc --from markdown --to json --lua-filter "$SPECCOMPILER_HOME/src/filter.lua" --metadata-file "$(basename "$P")" "$(basename "$P")" -o /dev/null\n' > /usr/local/bin/specc \
 && chmod +x /usr/local/bin/specc

WORKDIR /workspace
ENTRYPOINT ["specc"]

# ---------------------------------------------------------------------------
# Stage: full — lean + optional external renderers (Alpine community packages).
# deno: chart/echarts floats; plantuml (pulls a JRE) + graphviz: puml floats.
# ---------------------------------------------------------------------------
FROM lean AS full
RUN apk add --no-cache deno plantuml graphviz font-dejavu

# Chart rendering is model-owned (the abnt model carries the CHART float and
# its deno renderer); model overlay images (e.g. specc-abnt) pre-warm the deno
# cache themselves. The shared DENO_DIR location is established here so
# overlays and runtime agree on it.
ENV DENO_DIR=/opt/speccompiler/vendor/deno_cache \
    DENO_NO_UPDATE_CHECK=1
