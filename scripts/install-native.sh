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
#   WITH_PUML=0                          # skip java + plantuml.jar (puml floats)
#   WITH_LIBREOFFICE=0                   # skip LibreOffice + python3-uno
#                                        # (docx field update + PDF export)
#   SPECCOMPILER_HOME=<repo>             # source of src/ + models/ (default: this repo)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$SCRIPT_DIR")"
PREFIX="${PREFIX:-$HOME/.local/share/speccompiler}"
BINDIR="${BINDIR:-$HOME/.local/bin}"
HOME_DIR="${SPECCOMPILER_HOME:-$REPO}"
WITH_PUML="${WITH_PUML:-1}"
WITH_LIBREOFFICE="${WITH_LIBREOFFICE:-1}"
MIN_PANDOC="3.1"

# --- 1) system dependencies (Debian/Ubuntu) --------------------------------
if command -v apt-get >/dev/null 2>&1; then
  SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  echo "[1/4] apt dependencies..."
  $SUDO apt-get update -qq
  # Required by the official ABNT/USP DOCX template. Ubuntu's package fetches
  # the original Microsoft core-font archives after EULA acceptance.
  printf '%s\n' \
    'ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true' \
    | $SUDO debconf-set-selections
  $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq pandoc \
    build-essential pkg-config git curl unzip cmake peg \
    liblua5.4-dev libsqlite3-dev libzip-dev \
    poppler-utils fontconfig \
    ttf-mscorefonts-installer
  fc-cache -f
  [ "$WITH_PUML" = 1 ] && $SUDO apt-get install -y -qq default-jre-headless
  [ "$WITH_LIBREOFFICE" = 1 ] && $SUDO apt-get install -y -qq \
    libreoffice-writer libreoffice-math python3-uno
else
  echo "[1/4] non-apt system — ensure these are present: pandoc (>= ${MIN_PANDOC}, distro"
  echo "      package with shared liblua), gcc, make, cmake, pkg-config, git, curl, unzip,"
  echo "      lua5.4 headers, sqlite3 dev, libzip dev (peg is optional — built from"
  echo "      source when absent), Poppler, Fontconfig, and exact Times New"
  echo "      Roman/Arial/Courier New fonts. For docx field update / PDF export also"
  echo "      install LibreOffice Writer + Math and Python UNO. See the README."
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

# --- 4) the unified `specc` wrapper (native mode) + config ------------------
echo "[4/4] installing $BINDIR/specc + config ..."
mkdir -p "$BINDIR"
cp "$SCRIPT_DIR/specc" "$BINDIR/specc"
chmod +x "$BINDIR/specc"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler"
mkdir -p "$CONFIG_DIR"
# VAR="${VAR:-...}" lines keep exported environment variables in priority
{
  printf 'SPECC_MODE="${SPECC_MODE:-native}"\n'
  printf 'SPECCOMPILER_HOME="${SPECCOMPILER_HOME:-%s}"\n' "$HOME_DIR"
  printf 'SPECCOMPILER_DIST="${SPECCOMPILER_DIST:-%s}"\n' "$PREFIX"
} > "$CONFIG_DIR/env"

echo
echo "Done. SpecCompiler installed (stock pandoc + system-lua extensions)."
echo "  vendor:  $PREFIX/vendor"
echo "  wrapper: $BINDIR/specc   (ensure $BINDIR is on PATH)"
echo "  config:  $CONFIG_DIR/env (SPECC_MODE=native)"
echo "  source:  $HOME_DIR (src/ + models/)"
echo "Run:  specc build project.yaml"
