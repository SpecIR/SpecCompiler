# SpecCompiler on Windows (native)

A portable zip: Pandoc built from source with Lua DLL module support, the
native Lua modules, SpecCompiler itself and the command launcher. No container
engine, WSL, installer or admin rights are needed; the core works offline.

## Install

1. Download `SpecCompiler-<version>-windows-x64.zip` from the GitHub release.
2. Extract it anywhere, e.g. `%LOCALAPPDATA%\Programs\SpecCompiler`.
3. Optionally add its `bin` folder to your PATH (PowerShell):

```powershell
$dir = "$env:LOCALAPPDATA\Programs\SpecCompiler\bin"
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$dir", 'User')
```

Then, from cmd or PowerShell (new terminal):

```powershell
specc build project.yaml
specc test --junit
specc pandoc --version
```

## Optional tools

Everything below is found on PATH (or its standard install folder) when
present. Without it the feature reports a clear message and the rest still works.

| Tool | Needed for | Windows status |
|------|-----------|----------------|
| Java runtime | PlantUML diagrams (`puml` floats) | `plantuml.jar` is bundled; install Java yourself |
| LibreOffice | DOCX field update and PDF export | Found in `Program Files`; uses LibreOffice's own Python |
| Graphviz | Some PlantUML diagram types | Not bundled; install it if a diagram asks for `dot` |
| Deno | Model-owned charts (for example the ABNT model) | Not bundled; the core does not use it |

```powershell
winget install EclipseAdoptium.Temurin.21.JRE
winget install TheDocumentFoundation.LibreOffice
winget install Graphviz.Graphviz
```

The Linux image also ships Poppler and the Microsoft core fonts. Windows already
has the fonts, and nothing in the core needs Poppler. The ReqIF converter
(`python -m reqif.specir`) is a separate Python tool and is not bundled.

## Runtime

`bin\pandoc.exe` and the native modules in `vendor\` all link the same
`bin\lua54.dll`, so Pandoc loads lsqlite3, luv, luaamath and brimworks.zip
directly into its own Lua state. There is no separate host process.

`bin\specc.cmd` runs the small `specc.ps1` launcher with Windows PowerShell
(present on every Windows 10/11), which sets the Lua module paths and calls
Pandoc. It resolves the project path relative to the caller, builds from the
project's directory, supports paths with spaces and forwards Pandoc's exit
code. `SPECCOMPILER_HOME` can point at a source checkout and
`SPECCOMPILER_DIST` at the runtime/vendor tree; both default to the extracted
folder.

## Building the distribution

Everything is PowerShell. Put git, an x64 MinGW-w64 gcc + make (w64devkit),
CMake, GHC 9.6.7 and Cabal 3.12 on PATH, then:

```powershell
powershell -ExecutionPolicy Bypass -File windows\build.ps1 -Version 1.2.3
```

The script compiles Lua 5.4 as a DLL, builds the pinned Pandoc from source with
HsLua's `system-lua` flag against that DLL, builds the native modules against
the same DLL, stages the tree in `dist\windows`, runs
`windows\tests\native-modules.lua` inside the built Pandoc and writes
`dist\SpecCompiler-<version>-windows-x64.zip`. Versions are pinned in
`scripts\versions.env`; downloads and intermediate builds are cached in
`dist\.windows-build`.

`windows\tests\launcher.ps1` checks the launcher (quoting, working directory,
exit codes) against a mock `pandoc.exe` without needing the Haskell build.

The GitHub workflow builds the zip, extracts it like a user, checks the native
modules, runs the E2E suites, builds the documentation and attaches the zip to
`v*` releases.
