# Plan — Lean core: model-owned charts + a thin build on stock pandoc

Two tracks: **(1)** charts (and Deno/JS) leave the core and become **model-owned**
(abnt) — renderer + tests included; core ships Deno-free; plus the reusable *"a model
brings in its own dependency"* mechanism. **(2)** drop the from-source pandoc build and
make SpecCompiler a **thin overlay on stock pandoc** (apt natively; the official
`pandoc/*` image in Docker), leaving Java/PlantUML as the one remaining heavy native dep.

> **Correction note.** An earlier draft claimed stock pandoc couldn't host our compiled
> Lua C extensions (so we "must" compile pandoc with `+system-lua`). **That was wrong** —
> verified empirically on this machine (see the table). Stock pandoc links a *shared* Lua
> and loads our extensions fine. The plan below reflects the corrected reality.

---

## What was actually tested (proofs, on this box)

| Check | Result |
|---|---|
| apt pandoc `3.1.3+ds-2` (Ubuntu noble) — `ldd` | `liblua5.4.so.0 => /lib/x86_64-linux-gnu/…` (system **shared** lua) |
| `nm -D` of apt pandoc | lua C-API symbols are `U …@LUA_5.4` → resolved from the shared lib |
| In apt pandoc: `require("lsqlite3")`, `require("luv")` | **both `true`** — our `.so` (built vs Lua 5.4.7) load against system 5.4.6 |
| Real `specc build` of `docs/engineering_docs` under apt pandoc 3.1.3 | **"build complete, Processed 3 document(s)", rc=0** |
| `pandoc/core:3.9.0.2` (Alpine) — `ldd` | `liblua-5.4.so.0 => /usr/lib/…` (musl **shared** lua) |
| Our own `dist/bin/pandoc` (3.6.1) — `ldd` | also resolves the *system* `liblua5.4.so.0` |
| version-sensitive code | only `src/pipeline/shared/sourcepos_compat.lua`, which already branches on pandoc ≥ 3.1.10 |

**Conclusion:** both glibc (apt) and musl (`pandoc/core`) stock pandoc expose Lua via a
shared lib, so a `require()`'d C extension resolves its `lua_*` symbols. apt's older
3.1.3 even runs the full pipeline. We do **not** need to build pandoc ourselves.

## Prototype results (built + verified — 2026-06-05)

Both tracks were prototyped and run on this machine:

| Prototype | What it did | Result |
|---|---|---|
| **3.1 minimum** | `./tests/run.sh` forced onto apt pandoc **3.1.3** (full suite, charts/abnt/ooxml incl.) | **99 / 0** |
| **Native build** | a hand-assembled `dist` = **system pandoc 3.1.3** + `lsqlite3` **freshly compiled vs system `lua5.4-dev` + system `libsqlite3`** + the other `.so` + pure-Lua; **no custom pandoc, no vendored Lua** (`vendor/lua` absent). Ran the full suite via `SPECCOMPILER_DIST=<proto>`. | **99 / 0** |
| **Docker overlay** | `FROM pandoc/core:latest` → `apk add build-base lua5.4-dev sqlite-dev` → compile `lsqlite3` **for musl** vs the image's Lua → `require("lsqlite3")` inside the image's pandoc (build `assert`s the load) | **`MUSL_LSQLITE3_LOAD=true`**, build OK |

So **3.1 is a safe floor** (3.1.3 runs the whole suite), the **native install needs no
vendored Lua and no compiled pandoc** (apt pandoc + extensions built against system
`lua5.4-dev`), and the **`pandoc/core` overlay + musl-compiled extensions works** exactly
as hypothesized. The native extension build is a one-line `gcc` per `.so`
(`gcc -shared -fPIC -o lsqlite3.so lsqlite3.c -I/usr/include/lua5.4 -lsqlite3`); `luv`/`zip`
build the same way (cmake) against `libuv1-dev`/`libzip-dev`; `luaamath` needs `peg`/`leg`
+ the upstream `camoy/amath` source (it is the AsciiMath→MathML engine for the `math`
float — **core**, and is exactly what let `math` drop Deno).

**One caveat to verify, not assert:** pandoc's *official static release tarball* (jgm's
`pandoc-x.y-linux-amd64.tar.gz`) likely bundles Lua **statically without exporting
symbols** — i.e. that's the one flavor our extensions probably *cannot* load into. So the
native path should use the **distro/image shared-lua pandoc**, not the static release.
(TODO: confirm with one `nm -D` on the static binary.)

---

## Current dependency map (grounded in `scripts/build.sh`)

| Dependency | Purpose | Core / Optional | Today | Under this plan |
|---|---|---|---|---|
| **pandoc** | engine + hosts our Lua filter | **core** | compiled `+system-lua`, GHC/Cabal, **15–30 min** | **stock** (apt / `pandoc/*` image); no source build |
| **lua 5.4** (shared) | pandoc's VM | **core** | we compile `liblua5.4.so` | comes **with** pandoc's package/image |
| **lsqlite3** | SQLite SPEC-IR binding | **core** | compiled vs our lua | compiled vs **system** `lua5.4-dev` (glibc + musl) or shipped prebuilt |
| **luv** (libuv) | async + model loader | **core** | compiled | same |
| **brimworks/zip** | docx zipping | core-for-docx | compiled | same |
| **luaamath** | AsciiMath→MathML for the `math` float (replaced math's Deno) | **core** | compiled (needs `peg` + `camoy/amath`) | same |
| **sqlite** | IR engine | **core** | we compile the amalgamation | system `libsqlite3` (apt/apk) |
| dkjson / sha2 / slaxml | json/hash/xml (pure Lua) | **core** | vendored | vendored (trivial) |
| **deno** + echarts | **charts only** | optional | `[4/8]`+`[7/8]`, ~209 MB | **moves to abnt** (model-declared) |
| **java + plantuml.jar** | **puml only** | optional | `[1/8]`+`[5/8]`, ~80 MB | apt/apk java + jar; opt-in |
| reqif (python) | ReqIF only | optional | pip | apt python + pip; opt-in |

Net: the only things we still *build* are the **four small C extensions** (seconds, vs
system `lua5.4-dev` + `libsqlite3-dev` + `libuv1-dev`) — or we ship them prebuilt per
libc. Everything else is a package or a copy.

---

## Track 1 — Charts become model-owned (core goes Deno-free)

Unchanged from the prior draft; still valid:
- Move `models/default/types/floats/chart.lua` (full impl) + `src/tools/echarts-render.ts`
  + `gauss.lua` into the charts model (abnt), with `find_render_script()` made
  **model-aware** (search `models/<dctx.model>/tools/` first; `dctx.model` already
  available). The renderer becomes a model asset (resolved like `models/<t>/assets/` CSL).
- Move the chart **tests** (`tests/e2e/floats/vc_024_02`, `vc_025_01` + `test_fixtures/`)
  to `specc-abnt/tests/`.
- **Drop chart usage** in `docs/user_docs/manual.md` (4) and
  `docs/engineering_docs/requirements/extension.md` (1) — replace with a "charts are a
  model-provided capability" note. *(Open #2.)*
- Missing renderer → upgrade the existing silent-skip to a **VERIFY diagnostic**.

> **Open #1 — charts' home:** abnt (literal brief) vs a small reusable **`charts`
> capability-model** abnt `extends`. Recommend the `charts` model (reusable if sw_docs
> ever wants charts); default to abnt if you prefer concrete.

## Track 1b — How a model brings in its own dependency (the reusable seam)

1. **Declare** — `model.yaml` gains an **enforced** `requires: [charts]` (today the host
   never reads `model.yaml`; `requires` is inert).
2. **Enforce** — the host reads `model.yaml` in `load_model` and validates each capability
   (`charts` → `command_exists("deno")` + the renderer), failing **loudly** if absent.
   Extend HLR-EXT-010 + a VC.
3. **Carry** — the model ships its tool under `models/<name>/tools/` (resolved like
   `assets/`). abnt carries `tools/echarts-render.ts`.
4. **Provision** — optional `models/<name>/scripts/bootstrap.sh` the install/build runs
   when that model is selected (fetches Deno, caches echarts deps), so the **core** never
   pulls Deno. *(Open #3: bootstrap vs build-flag vs document-only — recommend bootstrap.)*

---

## Track 2 — Thin build on stock pandoc (the corrected, achievable version)

### Native install (apt) — "mostly wire PATH" is essentially right
1. `apt install pandoc` (brings shared `liblua5.4`) `+ default-jre-headless` (puml,
   optional) `+ libsqlite3-0` (and, if compiling extensions, `gcc lua5.4-dev
   libsqlite3-dev libuv1-dev`).
2. Provide the **four C extensions**: either compile-on-install (a `make` of seconds
   against system `lua5.4-dev`) **or** ship prebuilt `*.so` for common platforms
   (glibc x86_64/arm64). Pure-Lua libs (dkjson/sha2/slaxml) are just copied.
3. Drop our `src/` + `models/` + a `specc` wrapper that sets
   `LUA_PATH`/`LUA_CPATH`/`PATH` at the **system** pandoc + our extensions + `src`.
4. **No GHC/Cabal, no pandoc compile, no Deno, no vendored Lua/pandoc.** Install is a few
   apt packages + a tiny extension build (or copy) + PATH.
→ *Proven viable:* apt pandoc 3.1.3 already runs `specc build`.

### Docker — thin overlay on the official pandoc image (your idea, now confirmed)
```dockerfile
FROM pandoc/core:3.6   # or pandoc/latex for TeX/PDF; pin the tag for a known pandoc version
RUN apk add --no-cache build-base lua5.4-dev sqlite-dev libuv-dev   # musl toolchain
COPY src/tools/ /build/src/tools/
RUN <compile the 4 extensions for musl vs Alpine's lua5.4 -> /opt/speccompiler/vendor>
# optional layers:
RUN apk add --no-cache openjdk17-jre-headless && <fetch plantuml.jar>   # +puml
# (+charts: deno layer, only for abnt — model-declared, not here)
COPY src/ models/ /opt/speccompiler/
ENV LUA_PATH=... LUA_CPATH=... PATH=/opt/speccompiler/bin:$PATH
```
- The **musl compile** is exactly your suggestion and is *required* for Alpine (the
  `.so` must match the image's libc); `pandoc/core` linking shared `liblua-5.4` is what
  makes it load. Build the extensions **inside** the Alpine base so ABI matches.
- Result: the image is `official pandoc + ~4 small .so + our Lua + (opt) java`. A genuine
  thin overlay — builds in seconds, no GHC.
- If TeX/PDF is wanted, base on `pandoc/latex` (Alpine + TeX Live) instead of `pandoc/core`.

### The one thing to manage: pandoc version
- apt distro pandoc lags (Ubuntu noble = 3.1.3 — works, but old); `pandoc/core` tracks
  latest (3.9). We target ~3.6.1.
- Decide a **supported range** (e.g. ≥ 3.1.10 given `sourcepos_compat`), run the suite
  against the min and a recent pandoc, and **pin the Docker base tag**. For native, accept
  the distro pandoc if it meets the min, else point users at a newer package (backport/PPA)
  — *not* the static release tarball (the static-lua caveat above).
- Keep `scripts/build.sh`'s pandoc compile as an **optional/maintainer** path for exact
  pinning or air-gapped builds; it is no longer the default.

### Layering (what's core vs opt-in)
- **core:** stock pandoc + shared lua + the 4 C extensions + system sqlite + pure-Lua.
- **+puml:** java + plantuml.jar (apt/apk, opt-in or model `requires: [java]`).
- **+charts:** deno + echarts (abnt-owned, model-declared).
- **+reqif:** python + reqif (opt-in).

---

## Phased plan

**Phase 1 — charts → model-owned.** *(DONE 2026-06-10; final home: the abnt model owns charts — types/floats/chart.lua, types/views/gauss.lua, tools/echarts-render.ts in specc-abnt)* Move chart float + `echarts-render.ts` + gauss + the
chart tests into the charts model; model-aware `find_render_script`; drop core chart usage;
remove/gate the Deno build steps. → *Verify:* core suite green w/o Deno; abnt charts render;
`git grep deno src models/default` → 0.

**Phase 2 — model-dependency mechanism.** *(DONE 2026-06-10: manifest `requires:` loaded recursively by the host)* Host reads + enforces `model.yaml.requires`; abnt
declares `requires: [charts]` + carries `tools/echarts-render.ts` + `scripts/bootstrap.sh`.
→ *Verify:* abnt build with no Deno fails loudly; with bootstrap it renders.

**Phase 3 — stock-pandoc native install.** *(DONE: scripts/install-native.sh)* New `scripts/install.sh`: apt pandoc + (compile
or fetch prebuilt) extensions + copy `src`/`models` + `specc` wrapper. Add a pandoc
min-version check. Keep `build.sh` pandoc-compile as maintainer-only. → *Verify:* clean box
installs in well under a minute, no GHC; `specc build` works against apt pandoc.

**Phase 4 — Docker overlay on pandoc image.** *(DONE 2026-06-10: Dockerfile.lean lean+full, pinned pandoc/core:3.8)* Rebase the `Dockerfile` on `pandoc/core`
(and a `pandoc/latex` variant for PDF); compile the 4 extensions for musl in-image; layer
java(+puml) and the abnt deno(+charts) separately. → *Verify:* image builds in seconds from
the pandoc base; full suite green in-container; image is far smaller than the GHC toolchain.

**Phase 5 — (optional)** keep/trim the from-source `build.sh` as the maintainer/air-gapped
path; confirm + document the static-release-binary caveat.

---

## Verification (end state)

- `git grep deno src/ models/default` → 0; core install/image carries no Deno.
- Native: `apt install pandoc …` + extension build/copy + PATH → `specc build` works
  (proven on 3.1.3); no GHC/Cabal anywhere on the user path.
- Docker: `FROM pandoc/core` overlay builds in seconds; suite green in-container.
- abnt without its deno bootstrap → fails loudly (`requires: charts`); with it → renders.
- The four extensions load into the target pandoc (glibc native / musl Alpine), proven by
  a `require()` smoke test in CI for each base.

## Open decisions

1. **Charts' home** — abnt vs a reusable `charts` capability-model (recommend the latter).
2. **`user_docs` manual** documents charts — drop the live ones with a note, keep a
   screenshot, or move chart docs into the charts model?
3. **Provision model deps** — per-model `bootstrap.sh` (recommended) vs build flags vs docs.
4. **Native pandoc source** — accept the distro/apt pandoc (+min-version check) as the
   default, with the from-source build kept only for maintainers/air-gapped?
5. **Extensions** — ship **prebuilt `.so`** per platform (no compiler on install) vs
   compile-on-install (needs `lua5.4-dev`+`gcc`)? (Prebuilt = simplest UX; compile = most
   portable.)
6. **Docker base** — `pandoc/core` (small) as default + a `pandoc/latex` variant for PDF?
