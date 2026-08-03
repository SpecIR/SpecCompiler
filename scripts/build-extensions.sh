#!/usr/bin/env bash
# build-extensions.sh — build SpecCompiler's Lua C extensions + pure-Lua libs
# against the SYSTEM Lua 5.4 (no vendored Lua, no custom pandoc).
#
# Works on glibc (apt) and musl (Alpine) the same way — it links nothing Lua at
# compile time except the headers; the lua_* symbols resolve at dlopen against
# whatever shared liblua the host pandoc already loaded. Used by both the native
# installer and the pandoc/core Docker overlay.
#
# Usage:  build-extensions.sh <out_vendor_dir>
#   env overrides (auto-detected via pkg-config otherwise):
#     LUA_INCDIR   dir containing lua.h            (e.g. /usr/include/lua5.4)
#     LUA_SO       full path to the lua shared lib (for cmake LUA_LIBRARIES)
set -euo pipefail

OUT="${1:?usage: build-extensions.sh <out_vendor_dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/versions.env"

mkdir -p "$OUT/brimworks"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# --- detect system Lua 5.4 -------------------------------------------------
LUA_INCDIR="${LUA_INCDIR:-$(pkg-config --variable=includedir lua5.4 2>/dev/null || true)}"
if [ -n "$LUA_INCDIR" ] && [ ! -f "$LUA_INCDIR/lua.h" ] && [ -f "$LUA_INCDIR/lua5.4/lua.h" ]; then
  LUA_INCDIR="$LUA_INCDIR/lua5.4"
fi
[ -f "${LUA_INCDIR:-}/lua.h" ] || LUA_INCDIR=/usr/include/lua5.4
[ -f "$LUA_INCDIR/lua.h" ] || { echo "ERROR: lua.h not found (install lua5.4-dev / lua5.4-dev)"; exit 1; }
if [ -z "${LUA_SO:-}" ]; then
  LIBDIR="$(pkg-config --variable=libdir lua5.4 2>/dev/null || echo /usr/lib)"
  for cand in "$LIBDIR"/liblua5.4.so "$LIBDIR"/liblua-5.4.so "$LIBDIR"/liblua5.4.so.0 \
              /usr/lib/*/liblua5.4.so /usr/lib/liblua-5.4.so; do
    [ -e "$cand" ] && { LUA_SO="$cand"; break; }
  done
fi
echo "  Lua headers: $LUA_INCDIR"
echo "  Lua shared : ${LUA_SO:-<none — cmake will autodetect>}"

# --- lsqlite3 (vs SYSTEM sqlite; no static archive, no -llua) ---------------
if [ ! -f "$OUT/lsqlite3.so" ]; then
  echo "  building lsqlite3 ${LSQLITE3_VERSION}..."
  ( cd "$TMP" && curl -sL "https://lua.sqlite.org/home/zip/lsqlite3_v096.zip?uuid=${LSQLITE3_VERSION}" -o l.zip \
    && unzip -q l.zip && cd lsqlite3_v096 \
    && gcc -shared -fPIC -o "$OUT/lsqlite3.so" lsqlite3.c -I"$LUA_INCDIR" -lsqlite3 )
fi

# --- luv (bundled libuv; vs system Lua) ------------------------------------
if [ ! -f "$OUT/luv.so" ]; then
  echo "  building luv ${LUV_TAG}..."
  ( cd "$TMP" && git clone -q --depth 1 --branch "$LUV_TAG" --recurse-submodules https://github.com/luvit/luv.git \
    && cd luv && mkdir -p build && cd build \
    && cmake .. -DWITH_SHARED_LIBUV=OFF -DWITH_LUA_ENGINE=Lua -DLUA_BUILD_TYPE=System \
         -DLUA_INCLUDE_DIR="$LUA_INCDIR" ${LUA_SO:+-DLUA_LIBRARIES="$LUA_SO"} >/dev/null \
    && make -s && cp luv.so "$OUT/" )
fi

# --- brimworks/lua-zip (single C file; gcc directly vs system libzip) -------
# Its bundled CMakeLists predates CMake 3.5 and breaks on modern CMake (Alpine);
# lua_zip.c is one file, so compile it straight (module name: brimworks.zip).
if [ ! -f "$OUT/brimworks/zip.so" ]; then
  echo "  building brimworks/zip ${LUAZIP_TAG}..."
  ( cd "$TMP" && git clone -q --depth 1 --branch "$LUAZIP_TAG" https://github.com/brimworks/lua-zip.git \
    && cd lua-zip \
    && gcc -shared -fPIC -o "$OUT/brimworks/zip.so" lua_zip.c -I"$LUA_INCDIR" $(pkg-config --cflags --libs libzip) )
fi
# a missing libzip-dev/pkg-config leaves $(pkg-config ...) empty and gcc -shared
# still "succeeds" — the .so then fails only at runtime. Catch it here instead.
readelf -d "$OUT/brimworks/zip.so" | grep -q 'libzip' \
  || { echo "ERROR: zip.so is not linked against libzip (install libzip-dev + pkg-config and rebuild)"; exit 1; }

# --- luaamath (AsciiMath->MathML for the math float; needs peg/leg + amath) --
if [ ! -f "$OUT/luaamath.so" ]; then
  # leg (Ian Piumarta's peg) generates amath's parser. It is packaged on Debian
  # (apt: peg) but NOT on Alpine, so build it from source when absent.
  if ! command -v leg >/dev/null 2>&1; then
    echo "  leg not found — building peg from source..."
    ( cd "$TMP" && curl -sL "https://www.piumarta.com/software/peg/peg-0.1.18.tar.gz" -o peg.tgz \
      && tar xzf peg.tgz && cd peg-0.1.18 && make -s )
    mkdir -p "$TMP/legbin" && cp "$TMP"/peg-0.1.18/peg "$TMP"/peg-0.1.18/leg "$TMP/legbin/"
    export PATH="$TMP/legbin:$PATH"
  fi
  echo "  building luaamath ${AMATH_COMMIT:0:12}..."
  ( cd "$TMP" && git clone -q https://github.com/camoy/amath.git && cd amath \
    && git checkout -q "$AMATH_COMMIT" \
    && cp "$SOURCE_DIR/src/tools/amath/luaamath.c" "$SOURCE_DIR/src/tools/amath/Makefile" . \
    && make -s LUA_INC="$LUA_INCDIR" \
    && cp build/luaamath.so "$OUT/" )
fi

# --- pure-Lua libs (portable; no compile) ----------------------------------
[ -f "$OUT/dkjson.lua" ] || curl -sL "http://dkolf.de/dkjson-lua/dkjson-${DKJSON_VERSION}.lua" -o "$OUT/dkjson.lua"
[ -f "$OUT/sha2.lua" ]   || curl -sL "https://raw.githubusercontent.com/Egor-Skriptunoff/pure_lua_SHA/${SHA2_COMMIT}/sha2.lua" -o "$OUT/sha2.lua"
if [ ! -d "$OUT/slaxml" ]; then
  ( cd "$TMP" && git clone -q --depth 1 --branch "$SLAXML_TAG" https://github.com/Phrogz/SLAXML.git \
    && mkdir -p "$OUT/slaxml" && cp SLAXML/*.lua "$OUT/slaxml/" )
fi

# --- SQLite WASM (browser sqlite for the HTML web app search/filters/inspector) ---
# html5.lua embeds these from $DIST/vendor/sqlite/wasm/; without them the web app
# falls back to "SQLite WASM not available" and search/inspector are disabled.
if [ ! -f "$OUT/sqlite/wasm/sqlite3.wasm" ]; then
  echo "  downloading SQLite WASM ${SQLITE_VERSION}..."
  mkdir -p "$OUT/sqlite/wasm"
  ( cd "$TMP" && curl -sL "https://sqlite.org/${SQLITE_YEAR}/sqlite-wasm-${SQLITE_VERSION}.zip" -o sqlite-wasm.zip \
    && unzip -q sqlite-wasm.zip \
    && cp "sqlite-wasm-${SQLITE_VERSION}/jswasm/sqlite3.js"   "$OUT/sqlite/wasm/" \
    && cp "sqlite-wasm-${SQLITE_VERSION}/jswasm/sqlite3.wasm" "$OUT/sqlite/wasm/" )
fi

echo "  extensions ready in: $OUT"
ls "$OUT" | tr '\n' ' '; echo
