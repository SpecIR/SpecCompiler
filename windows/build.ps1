<#
windows/build.ps1 - build SpecCompiler's portable Windows distribution.

Writes dist/SpecCompiler-<version>-windows-x64.zip. Unzipped, it is used in
place; nothing is registered with Windows:

  bin/      pandoc.exe (built from source), lua54.dll, specc.cmd, specc.ps1,
            test.ps1, plantuml.cmd
  vendor/   native Lua DLL modules (lsqlite3, luv, luaamath, brimworks.zip),
            pure-Lua libraries, SQLite WASM, plantuml.jar
  src/ models/ tests/   SpecCompiler itself
  licenses/ third-party license texts and the exact Pandoc build plan

Pandoc and every native module link the same bin/lua54.dll, so Pandoc's own
Lua state can `require` them directly (the official Pandoc build cannot).

Requirements on PATH: git, gcc + make (x64 MinGW-w64, e.g.
w64devkit), cmake, ghc, cabal. Runs under Windows PowerShell 5.1 or PowerShell 7.
Downloads and intermediate builds are kept in dist/.windows-build (or $env:WORK)
and reused on the next run.

Usage: powershell -ExecutionPolicy Bypass -File windows\build.ps1 [-Version 1.2.3] [-OutDir dist\windows]
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$OutDir
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = Split-Path $PSScriptRoot -Parent
$Dist = Join-Path $Repo 'dist'
$Work = if ($env:WORK) { $env:WORK } else { Join-Path $Dist '.windows-build' }
if (-not $OutDir) { $OutDir = Join-Path $Dist 'windows' }
if (-not $Version) {
    try { $Version = & git -C $Repo describe --tags --always } catch { $Version = $null }
    if ($LASTEXITCODE -ne 0 -or -not $Version) { $Version = '0.0.0-dev' }
}
$Version = "$Version" -replace '^v', ''

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
# Windows' own bsdtar: w64devkit's busybox tar comes first on PATH and would write a plain tar named .zip.
$Tar = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $Tar)) { throw 'Windows tar.exe not found (needs Windows 10 1803 or later)' }
foreach ($tool in 'git', 'gcc', 'make', 'cmake', 'ghc', 'cabal') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "required build tool missing on PATH: $tool" }
}
$Pins = @{}
foreach ($line in Get-Content (Join-Path $Repo 'scripts\versions.env')) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)="([^"]*)"\s*$') { $Pins[$Matches[1]] = $Matches[2] }
}
function Fwd([string]$Path) { return $Path.Replace('\', '/') }
function Run([string]$Exe, [string[]]$Arguments, [string]$Cwd) {
    if ($Cwd) { Push-Location -LiteralPath $Cwd }
    try {
        & $Exe @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE" }
    } finally { if ($Cwd) { Pop-Location } }
}
function Fetch([string]$Url, [string]$File) {
    if (Test-Path -LiteralPath $File) { return }
    Write-Host "  fetching $Url"
    Invoke-WebRequest -UseBasicParsing $Url -OutFile "$File.part"
    Move-Item -LiteralPath "$File.part" -Destination $File -Force
}
function Extract([string]$Archive, [string]$Marker) {
    if (-not (Test-Path -LiteralPath $Marker)) { Run $Tar @('-xf', $Archive, '-C', $Work) }
}
function Clone([string]$Url, [string]$Ref, [string]$Dir, [switch]$Submodules) {
    if (Test-Path -LiteralPath $Dir) { return }
    $cloneArgs = @('-c', 'advice.detachedHead=false', 'clone', '-q', '--depth', '1', '--branch', $Ref)
    if ($Submodules) { $cloneArgs += @('--recurse-submodules', '--shallow-submodules') }
    Run git ($cloneArgs + @($Url, $Dir))
}
function Copy-Tree([string]$Source, [string]$Destination, [string[]]$ExcludeDirs) {
    $rc = @($Source, $Destination, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    if ($ExcludeDirs) { $rc += @('/XD') + $ExcludeDirs }
    & robocopy @rc | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy $Source -> $Destination failed ($LASTEXITCODE)" }
}

New-Item -ItemType Directory -Force $Work, $OutDir | Out-Null
$Work = (Resolve-Path -LiteralPath $Work).Path
$Out = (Resolve-Path -LiteralPath $OutDir).Path
if (-not $Out.StartsWith("$Dist\", [StringComparison]::OrdinalIgnoreCase)) { throw "output must be below $Dist" }
Get-ChildItem -LiteralPath $Out -Force | Remove-Item -Recurse -Force
$LuaLib = Join-Path $Work 'lua-lib'
New-Item -ItemType Directory -Force "$Out\bin", "$Out\vendor\brimworks", "$Out\licenses", $LuaLib | Out-Null
$Make = (Get-Command make).Source

# ---------------------------------------------------------------------------
Write-Host "[1/7] Lua $($Pins.LUA_VERSION) as a shared DLL"
# ---------------------------------------------------------------------------
Fetch "https://www.lua.org/ftp/lua-$($Pins.LUA_VERSION).tar.gz" "$Work\lua.tar.gz"
Extract "$Work\lua.tar.gz" "$Work\lua-$($Pins.LUA_VERSION)"
$LuaInc = "$Work\lua-$($Pins.LUA_VERSION)\src"
$luaSources = @(Get-ChildItem "$LuaInc\*.c" | Where-Object { $_.Name -notin 'lua.c', 'luac.c' } | ForEach-Object FullName)
Run gcc (@('-O2', '-shared', '-DLUA_BUILD_AS_DLL', '-o', "$Out\bin\lua54.dll", "-Wl,--out-implib,$LuaLib\liblua.dll.a") + $luaSources)
Copy-Item "$Work\lua-$($Pins.LUA_VERSION)\doc\readme.html" "$Out\licenses\Lua.html"

# ---------------------------------------------------------------------------
Write-Host "[2/7] Pandoc $($Pins.PANDOC_WIN_VERSION) from source (HsLua on bin\lua54.dll)"
# ---------------------------------------------------------------------------
$PandocSrc = "$Work\pandoc-$($Pins.PANDOC_WIN_VERSION)"
Clone 'https://github.com/jgm/pandoc.git' $Pins.PANDOC_WIN_VERSION $PandocSrc
# cabal reads this file; write it without a BOM.
[IO.File]::WriteAllText("$PandocSrc\cabal.project.local", @"
package pandoc
  flags: +embed_data_files
package pandoc-cli
  flags: +lua -server
package lua
  flags: +system-lua -pkg-config
  extra-include-dirs: $(Fwd $LuaInc)
  extra-lib-dirs: $(Fwd $LuaLib)
"@)
# Haskell packages such as network and unix-time run autoconf `configure`
# scripts. They need a real MSYS shell (Git for Windows' usr\bin): the shell in
# w64devkit cannot parse a Windows PATH, so configure never finds gcc or grep.
# It is put on PATH only for cabal, because its tar would shadow Windows tar.
$gitUsr = Join-Path (Split-Path (Split-Path (Get-Command git).Source -Parent) -Parent) 'usr\bin'
if (-not (Test-Path -LiteralPath "$gitUsr\sh.exe")) { throw "Git for Windows' MSYS shell not found at $gitUsr" }
$savedPath = $env:PATH
$env:PATH = "$gitUsr;$env:PATH"
try {
    Run cabal @('update') $PandocSrc
    Run cabal @('build', 'pandoc-cli:exe:pandoc') $PandocSrc
    Run cabal @('freeze') $PandocSrc
    Push-Location -LiteralPath $PandocSrc
    try { $pandocBin = (& cabal list-bin pandoc-cli:exe:pandoc | Select-Object -Last 1).Trim() } finally { Pop-Location }
} finally { $env:PATH = $savedPath }
Copy-Item -LiteralPath $pandocBin "$Out\bin\pandoc.exe"
Copy-Item "$PandocSrc\COPYING.md" "$Out\licenses\Pandoc-COPYING.md"
Copy-Item "$PandocSrc\COPYRIGHT" "$Out\licenses\Pandoc-COPYRIGHT"
Copy-Item "$PandocSrc\cabal.project.freeze" "$Out\licenses\pandoc-build.freeze"

# ---------------------------------------------------------------------------
Write-Host "[3/7] native module sources (SQLite, lsqlite3, luv, peg, amath, zlib, libzip, lua-zip)"
# ---------------------------------------------------------------------------
Fetch "https://sqlite.org/$($Pins.SQLITE_YEAR)/sqlite-amalgamation-$($Pins.SQLITE_VERSION).zip" "$Work\sqlite.zip"
Extract "$Work\sqlite.zip" "$Work\sqlite-amalgamation-$($Pins.SQLITE_VERSION)"
$SqliteDir = "$Work\sqlite-amalgamation-$($Pins.SQLITE_VERSION)"
Fetch "https://lua.sqlite.org/home/zip/lsqlite3_v096.zip?uuid=$($Pins.LSQLITE3_VERSION)" "$Work\lsqlite3.zip"
Extract "$Work\lsqlite3.zip" "$Work\lsqlite3_v096"
Clone 'https://github.com/luvit/luv.git' $Pins.LUV_TAG "$Work\luv" -Submodules
$UvDir = "$Work\luv\deps\libuv"
# Debian's archived copy of the upstream peg tarball (piumarta.com is often unreachable)
Fetch "https://deb.debian.org/debian/pool/main/p/peg/peg_$($Pins.PEG_VERSION).orig.tar.gz" "$Work\peg.tgz"
Extract "$Work\peg.tgz" "$Work\peg-$($Pins.PEG_VERSION)"
$PegDir = "$Work\peg-$($Pins.PEG_VERSION)"
$Leg = "$PegDir\leg.exe"
# Not peg's Makefile: it ends with `mv leg-new leg`, but gcc names the output leg-new.exe.
if (-not (Test-Path -LiteralPath $Leg)) { Run gcc @('-w', '-O2', '-DNDEBUG', "-I$PegDir\src", '-o', $Leg, "$PegDir\src\leg.c", "$PegDir\src\tree.c", "$PegDir\src\compile.c") }
if (-not (Test-Path -LiteralPath "$Work\amath")) {
    Run git @('clone', '-q', 'https://github.com/camoy/amath.git', "$Work\amath")
    Run git @('-C', "$Work\amath", 'checkout', '-q', $Pins.AMATH_COMMIT)
}
if (-not (Test-Path -LiteralPath "$Work\amath\src\amath.leg.c")) {
    # Forward slashes: leg copies these paths into #line directives, where backslashes are C escapes.
    Run $Leg @('-o', (Fwd "$Work\amath\src\amath.leg.c"), (Fwd "$Work\amath\src\amath.leg"))
}
Fetch "https://zlib.net/fossils/zlib-$($Pins.ZLIB_WIN_VERSION).tar.gz" "$Work\zlib.tar.gz"
Extract "$Work\zlib.tar.gz" "$Work\zlib-$($Pins.ZLIB_WIN_VERSION)"
Fetch "https://libzip.org/download/libzip-$($Pins.LIBZIP_WIN_VERSION).tar.gz" "$Work\libzip.tar.gz"
Extract "$Work\libzip.tar.gz" "$Work\libzip-$($Pins.LIBZIP_WIN_VERSION)"
Clone 'https://github.com/brimworks/lua-zip.git' $Pins.LUAZIP_TAG "$Work\lua-zip"

# ---------------------------------------------------------------------------
Write-Host "[4/7] compiling native Lua DLL modules"
# ---------------------------------------------------------------------------
# Same feature set the stock Ubuntu libsqlite3 ships (FTS5, math functions).
$sqliteDefs = @('-DSQLITE_ENABLE_FTS5', '-DSQLITE_ENABLE_MATH_FUNCTIONS', '-DSQLITE_ENABLE_COLUMN_METADATA', '-DSQLITE_THREADSAFE=1')
Run gcc (@('-O2', '-shared') + $sqliteDefs + @("-I$LuaInc", "-I$SqliteDir",
    "$Work\lsqlite3_v096\lsqlite3.c", "$SqliteDir\sqlite3.c", "-L$LuaLib", '-llua', '-o', "$Out\vendor\lsqlite3.dll"))

$uvSources = @(Get-ChildItem "$UvDir\src\*.c", "$UvDir\src\win\*.c" | ForEach-Object FullName)
Run gcc (@('-O2', '-shared', '-DWIN32_LEAN_AND_MEAN', '-D_WIN32_WINNT=0x0602', '-D_CRT_DECLARE_NONSTDC_NAMES=0',
    "-I$LuaInc", "-I$UvDir\include", "-I$UvDir\src", "-I$Work\luv\deps\lua-compat-5.3\c-api", "$Work\luv\src\luv.c") + $uvSources +
    @("-L$LuaLib", '-llua', '-lws2_32', '-liphlpapi', '-lpsapi', '-luserenv', '-luser32', '-ladvapi32', '-ldbghelp', '-lole32', '-lshell32',
    '-o', "$Out\vendor\luv.dll"))

Run gcc @('-O2', '-shared', '-D_GNU_SOURCE', "-I$LuaInc", "-I$Work\amath", "-I$Work\amath\src",
    "$Work\amath\src\amath.c", "$Work\amath\src\util.c", "$Repo\src\tools\amath\luaamath.c",
    "-L$LuaLib", '-llua', '-o', "$Out\vendor\luaamath.dll")

# brimworks.zip: zlib and libzip are linked statically into the module.
# CMAKE_SH=...-NOTFOUND lets "MinGW Makefiles" work with a sh.exe on PATH (w64devkit, Git).
$ZipDeps = "$Work\zip-deps"
$cmakeCommon = @('-G', 'MinGW Makefiles', "-DCMAKE_MAKE_PROGRAM=$(Fwd $Make)", '-DCMAKE_SH=CMAKE_SH-NOTFOUND',
    '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_INSTALL_PREFIX=$(Fwd $ZipDeps)", '-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
if (-not (Test-Path -LiteralPath "$ZipDeps\lib\libzlibstatic.a")) {
    Run cmake (@('-S', "$Work\zlib-$($Pins.ZLIB_WIN_VERSION)", '-B', "$Work\zlib-build", '-DZLIB_BUILD_EXAMPLES=OFF') + $cmakeCommon)
    Run cmake @('--build', "$Work\zlib-build", '--target', 'install')
}
if (-not (Test-Path -LiteralPath "$ZipDeps\lib\libzip.a")) {
    Run cmake (@('-S', "$Work\libzip-$($Pins.LIBZIP_WIN_VERSION)", '-B', "$Work\libzip-build",
        "-DCMAKE_PREFIX_PATH=$(Fwd $ZipDeps)", '-DBUILD_SHARED_LIBS=OFF', "-DZLIB_LIBRARY=$(Fwd $ZipDeps)/lib/libzlibstatic.a",
        '-DBUILD_TOOLS=OFF', '-DBUILD_REGRESS=OFF', '-DBUILD_EXAMPLES=OFF', '-DBUILD_DOC=OFF',
        '-DENABLE_BZIP2=OFF', '-DENABLE_LZMA=OFF', '-DENABLE_ZSTD=OFF',
        '-DENABLE_OPENSSL=OFF', '-DENABLE_GNUTLS=OFF', '-DENABLE_MBEDTLS=OFF') + $cmakeCommon)
    Run cmake @('--build', "$Work\libzip-build", '--target', 'install')
}
Run gcc @('-O2', '-shared', '-DZIP_STATIC', "-I$LuaInc", "-I$ZipDeps\include", "$Work\lua-zip\lua_zip.c",
    "-L$LuaLib", '-llua', "$ZipDeps\lib\libzip.a", "$ZipDeps\lib\libzlibstatic.a", '-lbcrypt',
    '-o', "$Out\vendor\brimworks\zip.dll")

Copy-Item "$Work\libzip-$($Pins.LIBZIP_WIN_VERSION)\LICENSE" "$Out\licenses\libzip.txt"
Copy-Item "$Work\zlib-$($Pins.ZLIB_WIN_VERSION)\README" "$Out\licenses\zlib.txt"
Copy-Item "$Work\luv\LICENSE.txt" "$Out\licenses\luv.txt"
Copy-Item "$UvDir\LICENSE" "$Out\licenses\libuv.txt"
# These projects carry their license notices in their source files.
Copy-Item "$Work\lsqlite3_v096\lsqlite3.c" "$Out\licenses\lsqlite3.c"
Copy-Item "$Work\lua-zip\lua_zip.c" "$Out\licenses\lua_zip.c"
Copy-Item "$Work\amath\src\amath.c" "$Out\licenses\amath.c"

# ---------------------------------------------------------------------------
Write-Host "[5/7] staging SpecCompiler, pure-Lua libraries, SQLite WASM, PlantUML"
# ---------------------------------------------------------------------------
Copy-Item "$PSScriptRoot\launcher\*" "$Out\bin\"
Copy-Tree "$Repo\src" "$Out\src"
Copy-Tree "$Repo\models\default" "$Out\models\default" @('build')
Copy-Tree "$Repo\models\sw_docs" "$Out\models\sw_docs" @('build')
Copy-Tree "$Repo\tests" "$Out\tests" @('build', 'reports')
Copy-Item "$Repo\LICENSE", "$Repo\NOTICE", "$Repo\THIRD_PARTY_NOTICES.md" $Out
[IO.File]::WriteAllText("$Out\VERSION", $Version)

$V = "$Out\vendor"
New-Item -ItemType Directory -Force "$V\slaxml", "$V\sqlite\wasm", "$V\plantuml" | Out-Null
Fetch "http://dkolf.de/dkjson-lua/dkjson-$($Pins.DKJSON_VERSION).lua" "$V\dkjson.lua"
Fetch "https://raw.githubusercontent.com/Egor-Skriptunoff/pure_lua_SHA/$($Pins.SHA2_COMMIT)/sha2.lua" "$V\sha2.lua"
Clone 'https://github.com/Phrogz/SLAXML.git' $Pins.SLAXML_TAG "$Work\SLAXML"
Copy-Item "$Work\SLAXML\*.lua" "$V\slaxml\"
Clone 'https://github.com/keplerproject/luacov.git' "v$($Pins.LUACOV_VERSION)" "$Work\luacov"
Copy-Item "$Work\luacov\src\*" $V -Recurse -Force
Fetch "https://sqlite.org/$($Pins.SQLITE_YEAR)/sqlite-wasm-$($Pins.SQLITE_VERSION).zip" "$Work\sqlite-wasm.zip"
Extract "$Work\sqlite-wasm.zip" "$Work\sqlite-wasm-$($Pins.SQLITE_VERSION)"
Copy-Item "$Work\sqlite-wasm-$($Pins.SQLITE_VERSION)\jswasm\sqlite3.js", "$Work\sqlite-wasm-$($Pins.SQLITE_VERSION)\jswasm\sqlite3.wasm" "$V\sqlite\wasm\"
# MIT build of PlantUML, verified against the pinned checksum (needs a Java runtime at use time).
Fetch "https://github.com/plantuml/plantuml/releases/download/v$($Pins.PLANTUML_VERSION)/plantuml-mit-$($Pins.PLANTUML_VERSION).jar" "$Work\plantuml.jar"
$jarHash = (Get-FileHash -LiteralPath "$Work\plantuml.jar" -Algorithm SHA256).Hash
if ($jarHash -ne $Pins.PLANTUML_WIN_SHA256) { Remove-Item "$Work\plantuml.jar"; throw "plantuml.jar SHA-256 mismatch: $jarHash" }
Copy-Item "$Work\plantuml.jar" "$V\plantuml\plantuml.jar"

# ---------------------------------------------------------------------------
Write-Host "[6/7] smoke test: native modules inside the built Pandoc"
# ---------------------------------------------------------------------------
$env:LUA_CPATH = "$(Fwd $Out)/vendor/?.dll"
$env:LUA_CPATH_5_4 = $env:LUA_CPATH
Run "$Out\bin\pandoc.exe" @('lua', "$PSScriptRoot\tests\native-modules.lua")

# ---------------------------------------------------------------------------
Write-Host "[7/7] packaging"
# ---------------------------------------------------------------------------
$Zip = Join-Path $Dist "SpecCompiler-$Version-windows-x64.zip"
Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
$entries = @(Get-ChildItem -LiteralPath $Out -Force | ForEach-Object Name)
Run $Tar (@('-a', '-cf', $Zip, '-C', $Out) + $entries)
Write-Host "Done: $Zip ($([math]::Round((Get-Item $Zip).Length / 1MB, 1)) MB)"
