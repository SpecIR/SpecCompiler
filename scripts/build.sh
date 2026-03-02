#!/bin/bash
# SpecCompiler Core - Build Script
# Single source of truth for building all vendor dependencies.
# Called by Dockerfile and usable standalone with --install for native setup.
#
# All versions are pinned via scripts/versions.env.
# Targets Debian/Ubuntu only.

set -e

# Ensure running with bash, not sh
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash, not sh"
    echo "Usage: bash $0 [options]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Source pinned versions
# ---------------------------------------------------------------------------
source "$SCRIPT_DIR/versions.env"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FORCE=false
INSTALL=false
SKIP_SYSTEM_DEPS=false
SKIP_DENO=false
SKIP_PANDOC=false
PREFIX=""
SOURCE_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE=true; shift ;;
    --install) INSTALL=true; shift ;;
    --skip-system-deps) SKIP_SYSTEM_DEPS=true; shift ;;
    --skip-deno) SKIP_DENO=true; shift ;;
    --skip-pandoc) SKIP_PANDOC=true; shift ;;
    --prefix) PREFIX="$2"; shift 2 ;;
    --source-dir) SOURCE_DIR="$2"; shift 2 ;;
    --help|-h)
        echo "Usage: bash $0 [options]"
        echo ""
        echo "Options:"
        echo "  --prefix DIR          Install prefix for build output (default: <repo>/dist)"
        echo "  --source-dir DIR      Location of src/tools/ (default: repo root)"
        echo "  --force               Rebuild everything"
        echo "  --install             Also install specc wrapper to ~/.local/bin"
        echo "  --skip-system-deps    Skip apt-get install"
        echo "  --skip-pandoc         Skip Pandoc compilation"
        echo "  --skip-deno           Skip Deno + TypeScript tools"
        exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Defaults
PREFIX="${PREFIX:-$REPO_DIR/dist}"
SOURCE_DIR="${SOURCE_DIR:-$REPO_DIR}"

echo "=== SpecCompiler Core Build ==="
echo "Prefix:     $PREFIX"
echo "Source dir:  $SOURCE_DIR"
echo ""

# Detect if we need sudo (not needed in Docker as root)
SUDO=""
if [ "$(id -u)" != "0" ]; then
    SUDO="sudo"
fi

# ---------------------------------------------------------------------------
# Version-marker helpers: skip rebuild only when artifact AND version match
# ---------------------------------------------------------------------------
version_matches() {
    local marker_file="$1"
    local expected="$2"
    [ -f "$marker_file" ] && [ "$(cat "$marker_file" 2>/dev/null)" = "$expected" ]
}

write_version() {
    local marker_file="$1"
    local version="$2"
    echo "$version" > "$marker_file"
}

# =============================================================================
# 1. System Dependencies
# =============================================================================
if [ "$SKIP_SYSTEM_DEPS" = false ]; then
    echo "[1/8] Installing system dependencies..."
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq \
        build-essential cmake git curl unzip ca-certificates pkg-config \
        libreadline-dev libgmp-dev libffi-dev zlib1g-dev \
        libzip-dev \
        peg default-jdk-headless graphviz
else
    echo "[1/8] Skipping system dependencies (--skip-system-deps)"
fi

# =============================================================================
# 2. Lua 5.4 (compiled from source)
# =============================================================================
LUA_PREFIX="$PREFIX/vendor/lua"
LUA_INCLUDE_DIR="$LUA_PREFIX/include"

echo "[2/8] Building Lua ${LUA_VERSION} from source..."
if [ "$FORCE" = false ] && [ -f "$LUA_PREFIX/lib/liblua5.4.so" ] && version_matches "$LUA_PREFIX/.version" "$LUA_VERSION"; then
    echo "  Lua ${LUA_VERSION} already built, skipping"
else
    BUILD_TMP_LUA=$(mktemp -d)
    curl -sL "https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz" | tar xz -C "$BUILD_TMP_LUA"
    cd "$BUILD_TMP_LUA/lua-${LUA_VERSION}"

    # Build with -fPIC so we can create a shared library
    make -s -j"$(nproc)" linux MYCFLAGS="-fPIC"

    # Install headers + libraries
    mkdir -p "$LUA_PREFIX/include" "$LUA_PREFIX/lib/pkgconfig" "$PREFIX/bin"
    cp src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h "$LUA_PREFIX/include/"
    cp src/liblua.a "$LUA_PREFIX/lib/liblua5.4.a"

    # Build shared library from the static archive (all objects have -fPIC)
    # Version script provides the LUA_5.4 symbol version that Pandoc expects
    # (matching Debian's liblua5.4 convention)
    cat > lua5.4.map << 'MAPEOF'
LUA_5.4 {
    global: *;
};
MAPEOF
    gcc -shared -o "$LUA_PREFIX/lib/liblua5.4.so.0" \
        -Wl,--whole-archive src/liblua.a -Wl,--no-whole-archive \
        -Wl,--soname,liblua5.4.so.0 \
        -Wl,--version-script=lua5.4.map \
        -lm -ldl
    ln -sf "liblua5.4.so.0" "$LUA_PREFIX/lib/liblua5.4.so"

    # Install interpreter (useful for testing)
    cp src/lua "$PREFIX/bin/lua5.4"
    strip "$PREFIX/bin/lua5.4"

    # Create pkg-config file for Pandoc's +system-lua +pkg-config
    cat > "$LUA_PREFIX/lib/pkgconfig/lua5.4.pc" << PKGEOF
prefix=$LUA_PREFIX
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: Lua
Description: Lua 5.4 language engine
Version: ${LUA_VERSION}
Libs: -L\${libdir} -llua5.4 -lm -ldl
Cflags: -I\${includedir}
PKGEOF

    cd "$REPO_DIR"
    rm -rf "$BUILD_TMP_LUA"
    echo "  Lua ${LUA_VERSION} built and installed to $LUA_PREFIX"
    write_version "$LUA_PREFIX/.version" "$LUA_VERSION"
    # Lua was rebuilt: invalidate native extensions that link against it
    rm -f "$PREFIX/vendor/.lsqlite3_version"
    rm -f "$PREFIX/vendor/.luv_version"
    rm -f "$PREFIX/vendor/brimworks/.version"
    rm -f "$PREFIX/vendor/.luaamath_version"
fi

# Export for downstream builds (Pandoc, C extensions)
export PKG_CONFIG_PATH="$LUA_PREFIX/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$LUA_PREFIX/lib:${LD_LIBRARY_PATH:-}"

# =============================================================================
# 3. Pandoc (compiled from source with system-lua)
# =============================================================================
if [ "$SKIP_PANDOC" = false ]; then
    echo "[3/8] Installing Pandoc ${PANDOC_VERSION} (compiled from source)..."
    if [ "$FORCE" = false ] && [ -x "$PREFIX/bin/pandoc" ] && version_matches "$PREFIX/bin/.pandoc_version" "$PANDOC_VERSION"; then
        echo "  Pandoc ${PANDOC_VERSION} already compiled, skipping"
    else
        # GHCup prefix: use GHCUP_PREFIX env if set, else $HOME
        GHCUP_BASE="${GHCUP_PREFIX:-$HOME}"

        # Install GHCup + GHC + cabal if not present
        if ! command -v ghcup &>/dev/null && [ ! -f "$GHCUP_BASE/.ghcup/bin/ghcup" ]; then
            echo "  Installing GHCup (GHC ${GHC_VERSION}, cabal ${CABAL_VERSION})..."
            curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | \
                BOOTSTRAP_HASKELL_NONINTERACTIVE=1 \
                BOOTSTRAP_HASKELL_GHC_VERSION=${GHC_VERSION} \
                BOOTSTRAP_HASKELL_CABAL_VERSION=${CABAL_VERSION} \
                BOOTSTRAP_HASKELL_INSTALL_NO_STACK=1 \
                GHCUP_INSTALL_BASE_PREFIX="$GHCUP_BASE" \
                sh
        fi
        export PATH="$GHCUP_BASE/.ghcup/bin:$PATH"

        echo "  Compiling Pandoc ${PANDOC_VERSION} with system-lua..."
        echo "  (This takes 15-30 minutes on first build)"
        mkdir -p "$PREFIX/bin"
        cabal update
        cabal install pandoc-cli-${PANDOC_VERSION} \
            --constraint="hslua +system-lua" \
            --constraint="lua +system-lua +pkg-config" \
            --constraint="pandoc +embed_data_files" \
            --constraint="pandoc-cli -server" \
            --enable-split-sections \
            --install-method=copy \
            --installdir="$PREFIX/bin"
        strip "$PREFIX/bin/pandoc"
        echo "  Pandoc ${PANDOC_VERSION} compiled and installed to $PREFIX/bin/pandoc"
        write_version "$PREFIX/bin/.pandoc_version" "$PANDOC_VERSION"
    fi
else
    echo "[3/8] Skipping Pandoc (--skip-pandoc)"
fi

# =============================================================================
# 4. Deno
# =============================================================================
if [ "$SKIP_DENO" = false ]; then
    echo "[4/8] Installing Deno ${DENO_VERSION}..."
    export DENO_TLS_CA_STORE=system

    if [ "$FORCE" = false ] && [ -x "$PREFIX/bin/deno" ] && version_matches "$PREFIX/bin/.deno_version" "$DENO_VERSION"; then
        echo "  Deno ${DENO_VERSION} already installed, skipping"
    else
        mkdir -p "$PREFIX/bin"
        DENO_URL="https://dl.deno.land/release/v${DENO_VERSION}/deno-x86_64-unknown-linux-gnu.zip"
        curl -fsSL "$DENO_URL" -o /tmp/deno.zip
        unzip -o /tmp/deno.zip -d "$PREFIX/bin/"
        chmod +x "$PREFIX/bin/deno"
        strip "$PREFIX/bin/deno"
        rm -f /tmp/deno.zip
        echo "  Deno ${DENO_VERSION} installed to $PREFIX/bin/deno"
        write_version "$PREFIX/bin/.deno_version" "$DENO_VERSION"
    fi
    export PATH="$PREFIX/bin:$PATH"
else
    echo "[4/8] Skipping Deno (--skip-deno)"
fi

# =============================================================================
# 5. PlantUML + Minimal JRE
# =============================================================================
echo "[5/8] Installing PlantUML ${PLANTUML_VERSION}..."

PLANTUML_DIR="$PREFIX/vendor/plantuml"
JRE_DIR="$PREFIX/jre"
JAR_PATH="$PLANTUML_DIR/plantuml.jar"
WRAPPER_PATH="$PREFIX/bin/plantuml"

if [ "$FORCE" = false ] && [ -f "$JAR_PATH" ] && [ -x "$WRAPPER_PATH" ] && version_matches "$PLANTUML_DIR/.version" "$PLANTUML_VERSION"; then
    echo "  PlantUML ${PLANTUML_VERSION} already installed, skipping"
else
    mkdir -p "$PLANTUML_DIR" "$PREFIX/bin"

    PLANTUML_URL="https://github.com/plantuml/plantuml/releases/download/v${PLANTUML_VERSION}/plantuml-${PLANTUML_VERSION}.jar"
    if curl -fSL "$PLANTUML_URL" -o "$JAR_PATH" 2>/dev/null; then
        chmod 644 "$JAR_PATH"

        # Build minimal JRE via jlink if available (saves ~200MB vs full JRE)
        if command -v jlink &>/dev/null; then
            echo "  Building minimal JRE via jlink..."
            rm -rf "$JRE_DIR"
            jlink --no-header-files --no-man-pages --compress=2 \
                --add-modules java.base,java.desktop,java.logging,java.xml \
                --output "$JRE_DIR"
            JAVA_CMD="\${SPECCOMPILER_DIST}/jre/bin/java"
        else
            # Fallback: use system java
            JAVA_CMD="java"
        fi

        cat > "$WRAPPER_PATH" << PUMLEOF
#!/bin/sh
exec $JAVA_CMD -jar \${SPECCOMPILER_DIST}/vendor/plantuml/plantuml.jar "\$@"
PUMLEOF
        chmod +x "$WRAPPER_PATH"
        echo "  PlantUML ${PLANTUML_VERSION} installed"
        write_version "$PLANTUML_DIR/.version" "$PLANTUML_VERSION"
    else
        echo "  WARNING: Failed to download PlantUML"
    fi
fi

# =============================================================================
# 6. Lua Native Extensions (vendor/)
# =============================================================================
echo "[6/8] Building Lua native extensions..."
mkdir -p "$PREFIX/vendor"
mkdir -p "$PREFIX/bin"

BUILD_TMP=""
build_init() {
    if [ -z "$BUILD_TMP" ]; then
        BUILD_TMP=$(mktemp -d)
        cd "$BUILD_TMP"
    fi
}

# --- SQLite from source (static library + WASM) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/sqlite/lib/libsqlite3.a" ] && version_matches "$PREFIX/vendor/sqlite/.version" "$SQLITE_VERSION"; then
    echo "  SQLite ${SQLITE_VERSION} already built, skipping"
else
    echo "  Building SQLite ${SQLITE_VERSION} from source..."
    build_init
    mkdir -p "$PREFIX/vendor/sqlite/lib"
    mkdir -p "$PREFIX/vendor/sqlite/wasm"

    curl -sL "https://sqlite.org/${SQLITE_YEAR}/sqlite-amalgamation-${SQLITE_VERSION}.zip" -o sqlite-amalgamation.zip
    unzip -q sqlite-amalgamation.zip
    cd "sqlite-amalgamation-${SQLITE_VERSION}"

    gcc -c -O2 -fPIC \
        -DSQLITE_ENABLE_FTS5 \
        -DSQLITE_ENABLE_JSON1 \
        -DSQLITE_THREADSAFE=1 \
        sqlite3.c -o sqlite3.o
    ar rcs "$PREFIX/vendor/sqlite/lib/libsqlite3.a" sqlite3.o
    cp sqlite3.h "$PREFIX/vendor/sqlite/"
    rm -f sqlite3.o
    cd "$BUILD_TMP"

    echo "  Downloading SQLite WASM..."
    curl -sL "https://sqlite.org/${SQLITE_YEAR}/sqlite-wasm-${SQLITE_VERSION}.zip" -o sqlite-wasm.zip
    unzip -q sqlite-wasm.zip
    cp "sqlite-wasm-${SQLITE_VERSION}/jswasm/sqlite3.js" "$PREFIX/vendor/sqlite/wasm/"
    cp "sqlite-wasm-${SQLITE_VERSION}/jswasm/sqlite3.wasm" "$PREFIX/vendor/sqlite/wasm/"
    echo "  SQLite ${SQLITE_VERSION} built"
    write_version "$PREFIX/vendor/sqlite/.version" "$SQLITE_VERSION"
    # SQLite was rebuilt: invalidate lsqlite3
    rm -f "$PREFIX/vendor/.lsqlite3_version"
fi

# --- lsqlite3 (linked against our static SQLite + locally-built Lua) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/lsqlite3.so" ] && version_matches "$PREFIX/vendor/.lsqlite3_version" "$LSQLITE3_VERSION"; then
    echo "  lsqlite3 ${LSQLITE3_VERSION} already built, skipping"
else
    echo "  Building lsqlite3.so (${LSQLITE3_VERSION})..."
    build_init
    curl -sL "https://lua.sqlite.org/home/zip/lsqlite3_v096.zip?uuid=${LSQLITE3_VERSION}" -o lsqlite3.zip
    unzip -q lsqlite3.zip && cd lsqlite3_v096
    gcc -shared -fPIC -o lsqlite3.so lsqlite3.c \
        -I"$LUA_INCLUDE_DIR" \
        -I"$PREFIX/vendor/sqlite" \
        -L"$LUA_PREFIX/lib" -llua5.4 \
        -Wl,--whole-archive "$PREFIX/vendor/sqlite/lib/libsqlite3.a" -Wl,--no-whole-archive \
        -lpthread -ldl
    cp lsqlite3.so "$PREFIX/vendor/"
    cd "$BUILD_TMP"
    write_version "$PREFIX/vendor/.lsqlite3_version" "$LSQLITE3_VERSION"
fi

# --- luv (libuv bindings, pinned tag — bundled libuv, no system dep) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/luv.so" ] && version_matches "$PREFIX/vendor/.luv_version" "$LUV_TAG"; then
    echo "  luv ${LUV_TAG} already built, skipping"
else
    echo "  Building luv.so (${LUV_TAG})..."
    build_init
    git clone -q --depth 1 --branch "${LUV_TAG}" --recurse-submodules https://github.com/luvit/luv.git
    cd luv && mkdir build && cd build
    cmake .. \
        -DWITH_SHARED_LIBUV=OFF \
        -DWITH_LUA_ENGINE=Lua \
        -DLUA_BUILD_TYPE=System \
        -DLUA_INCLUDE_DIR="$LUA_INCLUDE_DIR" \
        -DLUA_LIBRARIES="$LUA_PREFIX/lib/liblua5.4.so" \
        > /dev/null
    make -s && cp luv.so "$PREFIX/vendor/"
    cd "$BUILD_TMP"
    write_version "$PREFIX/vendor/.luv_version" "$LUV_TAG"
fi

# --- brimworks/zip (pinned tag) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/brimworks/zip.so" ] && version_matches "$PREFIX/vendor/brimworks/.version" "$LUAZIP_TAG"; then
    echo "  brimworks/zip ${LUAZIP_TAG} already built, skipping"
else
    echo "  Building brimworks/zip.so (${LUAZIP_TAG})..."
    build_init
    git clone -q --depth 1 --branch "${LUAZIP_TAG}" https://github.com/brimworks/lua-zip.git
    cd lua-zip
    cmake \
        -DLUA_INCLUDE_DIR="$LUA_INCLUDE_DIR" \
        -DLUA_LIBRARIES="$LUA_PREFIX/lib/liblua5.4.so" \
        . > /dev/null
    make -s
    mkdir -p "$PREFIX/vendor/brimworks"
    cp brimworks/zip.so "$PREFIX/vendor/brimworks/"
    cd "$BUILD_TMP"
    write_version "$PREFIX/vendor/brimworks/.version" "$LUAZIP_TAG"
fi

# --- luaamath (pinned commit) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/luaamath.so" ] && version_matches "$PREFIX/vendor/.luaamath_version" "$AMATH_COMMIT"; then
    echo "  luaamath ${AMATH_COMMIT:0:12} already built, skipping"
else
    echo "  Building luaamath.so (${AMATH_COMMIT:0:12})..."
    build_init
    git clone -q https://github.com/camoy/amath.git
    cd amath
    git checkout -q "${AMATH_COMMIT}"
    cp "$SOURCE_DIR/src/tools/amath/luaamath.c" .
    cp "$SOURCE_DIR/src/tools/amath/Makefile" .
    make -s LUA_INC="$LUA_INCLUDE_DIR"
    cp build/luaamath.so "$PREFIX/vendor/"
    cd "$BUILD_TMP"
    write_version "$PREFIX/vendor/.luaamath_version" "$AMATH_COMMIT"
fi

# --- dkjson (pure Lua, pinned version) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/dkjson.lua" ] && version_matches "$PREFIX/vendor/.dkjson_version" "$DKJSON_VERSION"; then
    echo "  dkjson ${DKJSON_VERSION} already installed, skipping"
else
    echo "  Downloading dkjson.lua (${DKJSON_VERSION})..."
    curl -sL "http://dkolf.de/dkjson-lua/dkjson-${DKJSON_VERSION}.lua" -o "$PREFIX/vendor/dkjson.lua"
    write_version "$PREFIX/vendor/.dkjson_version" "$DKJSON_VERSION"
fi

# --- sha2 (pure Lua, pinned commit) ---
if [ "$FORCE" = false ] && [ -f "$PREFIX/vendor/sha2.lua" ] && version_matches "$PREFIX/vendor/.sha2_version" "$SHA2_COMMIT"; then
    echo "  sha2 ${SHA2_COMMIT:0:12} already installed, skipping"
else
    echo "  Downloading sha2.lua (${SHA2_COMMIT:0:12})..."
    curl -sL "https://raw.githubusercontent.com/Egor-Skriptunoff/pure_lua_SHA/${SHA2_COMMIT}/sha2.lua" \
        -o "$PREFIX/vendor/sha2.lua"
    write_version "$PREFIX/vendor/.sha2_version" "$SHA2_COMMIT"
fi

# --- SLAXML (pure Lua, pinned tag) ---
if [ "$FORCE" = false ] && [ -d "$PREFIX/vendor/slaxml" ] && version_matches "$PREFIX/vendor/slaxml/.version" "$SLAXML_TAG"; then
    echo "  slaxml ${SLAXML_TAG} already installed, skipping"
else
    echo "  Downloading SLAXML (${SLAXML_TAG})..."
    build_init
    git clone -q --depth 1 --branch "${SLAXML_TAG}" https://github.com/Phrogz/SLAXML.git slaxml
    rm -rf slaxml/.git
    cp -r slaxml "$PREFIX/vendor/"
    write_version "$PREFIX/vendor/slaxml/.version" "$SLAXML_TAG"
fi

# --- luacov (pure Lua, pinned version) ---
if [ "$FORCE" = false ] && [ -d "$PREFIX/vendor/luacov" ] && version_matches "$PREFIX/vendor/luacov/.version" "$LUACOV_VERSION"; then
    echo "  luacov ${LUACOV_VERSION} already installed, skipping"
else
    echo "  Downloading luacov (${LUACOV_VERSION})..."
    build_init
    curl -sL "https://github.com/keplerproject/luacov/archive/v${LUACOV_VERSION}.tar.gz" | tar xz
    mkdir -p "$PREFIX/vendor/luacov/reporter"
    cp "luacov-${LUACOV_VERSION}/src/luacov/"*.lua "$PREFIX/vendor/luacov/"
    write_version "$PREFIX/vendor/luacov/.version" "$LUACOV_VERSION"
fi

# Cleanup temp directory
cd "$REPO_DIR"
[ -n "$BUILD_TMP" ] && rm -rf "$BUILD_TMP"

# =============================================================================
# 7. TypeScript Utilities (Deno runtime + cached deps)
# =============================================================================
if [ "$SKIP_DENO" = false ]; then
    echo "[7/8] Caching TypeScript dependencies..."
    mkdir -p "$PREFIX/vendor/deno_cache"

    DENO_DIR="$PREFIX/vendor/deno_cache" \
        "$PREFIX/bin/deno" cache --no-check \
        "$SOURCE_DIR/src/tools/echarts-render.ts" \
        "$SOURCE_DIR/src/tools/mml2omml.ts"

    # Create wrapper scripts that use the Deno runtime + cached deps
    # SPECCOMPILER_DIST = binaries/vendor, SPECCOMPILER_HOME = source code
    cat > "$PREFIX/bin/echarts-render" << 'EOF'
#!/bin/sh
exec "${SPECCOMPILER_DIST}/bin/deno" run --no-check --cached-only --allow-read --allow-write --allow-env --allow-net --allow-ffi --allow-sys "${SPECCOMPILER_HOME}/src/tools/echarts-render.ts" "$@"
EOF
    chmod +x "$PREFIX/bin/echarts-render"

    cat > "$PREFIX/bin/mml2omml" << 'EOF'
#!/bin/sh
exec "${SPECCOMPILER_DIST}/bin/deno" run --no-check --cached-only --allow-read "${SPECCOMPILER_HOME}/src/tools/mml2omml.ts" "$@"
EOF
    chmod +x "$PREFIX/bin/mml2omml"

    echo "  TypeScript deps cached, wrapper scripts created"
else
    echo "[7/8] Skipping TypeScript utilities (--skip-deno)"
fi

# =============================================================================
# 8. Create speccompiler-core wrapper
# =============================================================================
echo "[8/8] Creating speccompiler-core wrapper..."

cat > "$PREFIX/bin/speccompiler-core" << 'WRAPPER'
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# SPECCOMPILER_DIST: where binaries and vendor libs live (parent of bin/)
export SPECCOMPILER_DIST="$(dirname "$SCRIPT_DIR")"
# SPECCOMPILER_HOME: where src/ and models/ live
# - Local dev: parent of dist/ (i.e. repo root)
# - Docker: set via ENV in Dockerfile (equals SPECCOMPILER_DIST)
export SPECCOMPILER_HOME="${SPECCOMPILER_HOME:-$(dirname "$SPECCOMPILER_DIST")}"
export LUA_PATH="${SPECCOMPILER_HOME}/src/?.lua;${SPECCOMPILER_HOME}/src/?/init.lua;${SPECCOMPILER_HOME}/?.lua;${SPECCOMPILER_HOME}/?/init.lua;${SPECCOMPILER_DIST}/vendor/?.lua;${SPECCOMPILER_DIST}/vendor/?/init.lua;${SPECCOMPILER_DIST}/vendor/slaxml/?.lua;${LUA_PATH:-}"
export LUA_CPATH="${SPECCOMPILER_DIST}/vendor/?.so;${SPECCOMPILER_DIST}/vendor/?/?.so;${LUA_CPATH:-}"
export LD_LIBRARY_PATH="${SPECCOMPILER_DIST}/vendor/lua/lib:${LD_LIBRARY_PATH:-}"
export DENO_DIR="${SPECCOMPILER_DIST}/vendor/deno_cache"
export PATH="${SPECCOMPILER_DIST}/bin:${PATH}"
if [ "$1" = "build" ]; then shift; fi
PROJECT_FILE="${1:-project.yaml}"
if [ ! -f "$PROJECT_FILE" ]; then
    echo "Error: $PROJECT_FILE not found"
    exit 1
fi
# Change to project file's directory so relative paths in project.yaml
# (doc_files, output_dir, etc.) resolve correctly
PROJECT_DIR="$(cd "$(dirname "$PROJECT_FILE")" && pwd)"
PROJECT_NAME="$(basename "$PROJECT_FILE")"
cd "$PROJECT_DIR"
PANDOC="${SPECCOMPILER_DIST}/bin/pandoc"
[ -x "$PANDOC" ] || PANDOC="pandoc"
exec "$PANDOC" \
    --from markdown \
    --to json \
    --lua-filter="${SPECCOMPILER_HOME}/src/filter.lua" \
    --metadata-file "$PROJECT_NAME" \
    "$PROJECT_NAME" \
    -o /dev/null
WRAPPER
chmod +x "$PREFIX/bin/speccompiler-core"

echo ""
echo "=== Build Complete ==="
echo "Vendor libs: $PREFIX/vendor/"
echo "Binaries:    $PREFIX/bin/"
echo ""

# =============================================================================
# Optional: Install native wrapper (--install)
# =============================================================================
if [ "$INSTALL" = true ]; then
    echo "Setting up command-line tools..."

    WRAPPER_DIR="$HOME/.local/bin"
    mkdir -p "$WRAPPER_DIR"
    WRAPPER_FILE="$WRAPPER_DIR/specc"
    rm -f "$WRAPPER_FILE"
    cat > "$WRAPPER_FILE" << NATIVEOF
#!/bin/bash
set -e

usage() {
    echo "SpecCompiler"
    echo ""
    echo "Usage: specc build [project.yaml]"
    echo ""
    echo "  Build the project (default: project.yaml)"
}

case "\${1:-}" in
    build)  shift; exec "$PREFIX/bin/speccompiler-core" build "\$@" ;;
    -h|--help|help|"") usage ;;
    *)  echo "Unknown command: \$1"; usage; exit 1 ;;
esac
NATIVEOF
    chmod +x "$WRAPPER_FILE"

    # Add to PATH if not already present
    if [ -f "$HOME/.bashrc" ] && ! grep -q ".local/bin" "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Added by SpecCompiler installer" >> "$HOME/.bashrc"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        echo "  Added PATH to ~/.bashrc"
        echo ""
        echo "Run: source ~/.bashrc"
    fi

    echo ""
    echo "=== Native Installation Complete ==="
    echo "Run: specc build project.yaml"
else
    echo "To use: $PREFIX/bin/speccompiler-core project.yaml"
fi
