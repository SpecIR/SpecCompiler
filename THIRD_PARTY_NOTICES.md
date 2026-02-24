# Third-Party Notices

SpecCompiler Core includes, bundles, and/or invokes third-party software.

### Lua Runtime

| Component | Version | Source | License |
|-----------|---------|--------|---------|
| Lua | 5.4.7 | https://www.lua.org | MIT (Lua license) |
| SQLite (amalgamation) | 3470200 | https://sqlite.org | **Public Domain** |
| lsqlite3 | v0.9.6 | https://lua.sqlite.org | MIT |
| luv (bundles libuv) | 1.48.0-2 | https://github.com/luvit/luv | Apache-2.0 (luv) + MIT (libuv) |
| brimworks/lua-zip | v0.2.0 | https://github.com/brimworks/lua-zip | MIT |
| luaamath (amath binding) | 1b9e2f1ae313 | https://github.com/camoy/amath | MIT |
| peg | — | system package | MIT | Build amath parser |
| dkjson | 2.8 | http://dkolf.de/dkjson-lua | MIT |
| pure\_lua\_SHA (sha2.lua) | 6adac177c16c | https://github.com/Egor-Skriptunoff/pure_lua_SHA | MIT |
| SLAXML | v0.8 | https://github.com/Phrogz/SLAXML | MIT |

### Deno Runtime

| Component | Version | Source | License |
|-----------|---------|--------|---------|
| Deno | 2.6.4 | https://github.com/denoland/deno | MIT |
| echarts | 5.5.1 | https://github.com/apache/echarts | Apache-2.0 |
| @resvg/resvg-js | 2.6.2 | https://github.com/thx/resvg-js | MPL-2.0 |
| zrender | 5.6.0 | https://github.com/ecomfe/zrender | BSD-3-Clause |
| @std/path | 1.x | https://jsr.io/@std/path | MIT |
| @std/fs | 1.x | https://jsr.io/@std/fs | MIT |
| mathml2omml | 0.5.0 | https://github.com/niclasfr/mathml2omml | **LGPL-3.0-or-later** |
| tslib | 2.3.0 | https://github.com/Microsoft/tslib | 0BSD |

### Python 3 Runtime

| Component | Version | Source | License |
|-----------|---------|--------|---------|
| CPython | 3.11.x (Debian Bookworm) | https://www.python.org | PSF-2.0 |
| reqif | 0.0.48 | https://github.com/strictdoc-project/reqif | Apache-2.0 |

### Tools

| Component | Version | Source | License | 
|-----------|---------|--------|---------|
| Pandoc CLI | 3.6.1 | https://github.com/jgm/pandoc | **GPL-2.0-or-later** |
| PlantUML | 1.2024.8 | https://github.com/plantuml/plantuml | **GPL-3.0-or-later** |


| Runtime Dependency | Source | License |
|--------------------|--------|---------|
| OpenJDK JRE (minimal, via jlink) | https://openjdk.org | GPL-2.0 + Classpath Exception |
| Graphviz | https://graphviz.org | EPL-1.0 |


| Component | Version | Source | License | Purpose |
|-----------|---------|--------|---------|---------|
| luacov | 0.15.0 | https://github.com/keplerproject/luacov | MIT | Test coverage |
