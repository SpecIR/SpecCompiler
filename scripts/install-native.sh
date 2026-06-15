#!/usr/bin/env bash
# install-native.sh — install SpecCompiler on top of the DISTRO's pandoc.
#
# No custom pandoc, no vendored Lua: the distro's pandoc links a shared
# liblua5.4, so our four C extensions (compiled here against the system Lua)
# load straight into its filter VM. This is the fast/simple native path —
# "apt the deps, build four tiny .so, wire PATH".
#
#   PREFIX=~/.local/share/speccompiler   # where vendor/ lands
#   BINDIR=~/.local/bin                  # where the `specc` wrapper lands
#   WITH_PUML=1                          # also install java + plantuml.jar (puml floats)
#   SPECCOMPILER_HOME=<repo>             # source of src/ + models/ (default: this repo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
PREFIX="${PREFIX:-$HOME/.local/share/speccompiler}"
BINDIR="${BINDIR:-$HOME/.local/bin}"
HOME_DIR="${SPECCOMPILER_HOME:-$REPO}"
WITH_PUML="${WITH_PUML:-0}"
MIN_PANDOC="3.1"

# --- 1) system dependencies (Debian/Ubuntu) --------------------------------
if command -v apt-get >/dev/null 2>&1; then
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  echo "[1/4] apt dependencies..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq pandoc \
    build-essential pkg-config git curl unzip cmake peg \
    liblua5.4-dev libsqlite3-dev libuv1-dev libzip-dev
  [ "$WITH_PUML" = 1 ] && $SUDO apt-get install -y -qq default-jre-headless
else
  echo "[1/4] non-apt system — ensure these are present: pandoc, gcc, cmake, pkg-config,"
  echo "      git, curl, peg, lua5.4-dev, libsqlite3-dev, libuv-dev, libzip-dev"
fi

# --- 2) pandoc present + new enough (links shared liblua5.4) ----------------
command -v pandoc >/dev/null 2>&1 || { echo "ERROR: pandoc not found"; exit 1; }
PV="$(pandoc --version | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
echo "[2/4] pandoc $PV (min $MIN_PANDOC)"
if ! printf '%s\n%s\n' "$MIN_PANDOC" "$PV" | sort -V -C; then
  echo "ERROR: pandoc $PV is older than $MIN_PANDOC — install a newer distro pandoc."
  echo "       (Do NOT use the official static release tarball — it bundles a sealed Lua"
  echo "        and cannot load our C extensions; use the distro/package pandoc.)"
  exit 1
fi
if ! ldd "$(command -v pandoc)" 2>/dev/null | grep -qi 'liblua'; then
  echo "WARNING: this pandoc does not link a shared liblua — our C extensions may fail to"
  echo "         load. Prefer the distro package pandoc (apt), not a static binary."
fi

# --- 3) build the four C extensions + pure-Lua libs vs system Lua -----------
echo "[3/4] building extensions into $PREFIX/vendor ..."
mkdir -p "$PREFIX/vendor"
bash "$SCRIPT_DIR/build-extensions.sh" "$PREFIX/vendor"

# optional: PlantUML (java) for puml floats
if [ "$WITH_PUML" = 1 ]; then
  . "$SCRIPT_DIR/versions.env"
  mkdir -p "$PREFIX/vendor/plantuml" "$PREFIX/bin"
  [ -f "$PREFIX/vendor/plantuml/plantuml.jar" ] || \
    curl -sL "https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar" \
      -o "$PREFIX/vendor/plantuml/plantuml.jar"
  printf '#!/bin/sh\nexec java -jar "%s/vendor/plantuml/plantuml.jar" "$@"\n' "$PREFIX" > "$PREFIX/bin/plantuml"
  chmod +x "$PREFIX/bin/plantuml"
fi

# --- 4) the `specc` wrapper (stock pandoc + our vendor + our src/models) ----
echo "[4/4] writing $BINDIR/specc ..."
mkdir -p "$BINDIR"
cat > "$BINDIR/specc" <<WRAP
#!/usr/bin/env bash
set -e
export SPECCOMPILER_HOME="\${SPECCOMPILER_HOME:-$HOME_DIR}"
export SPECCOMPILER_DIST="$PREFIX"
export LUA_PATH="\$SPECCOMPILER_HOME/src/?.lua;\$SPECCOMPILER_HOME/src/?/init.lua;\$SPECCOMPILER_HOME/?.lua;\$SPECCOMPILER_HOME/?/init.lua;\$SPECCOMPILER_DIST/vendor/?.lua;\$SPECCOMPILER_DIST/vendor/slaxml/?.lua;\${LUA_PATH:-}"
export LUA_CPATH="\$SPECCOMPILER_DIST/vendor/?.so;\$SPECCOMPILER_DIST/vendor/?/?.so;\${LUA_CPATH:-}"
export PATH="\$SPECCOMPILER_DIST/bin:\$PATH"
[ "\${1:-}" = build ] && shift
P="\${1:-project.yaml}"
cd "\$(dirname "\$P")"
exec pandoc --from markdown --to json \\
  --lua-filter "\$SPECCOMPILER_HOME/src/filter.lua" \\
  --metadata-file "\$(basename "\$P")" "\$(basename "\$P")" -o /dev/null
WRAP
chmod +x "$BINDIR/specc"

echo
echo "Done. SpecCompiler installed (stock pandoc + system-lua extensions)."
echo "  vendor: $PREFIX/vendor"
echo "  wrapper: $BINDIR/specc   (ensure $BINDIR is on PATH)"
echo "  source:  $HOME_DIR (src/ + models/)"
echo "Run:  specc build project.yaml"
