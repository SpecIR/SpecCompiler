# Install & Distribution — Design (v2, decisions confirmed 2026-08-02)

> **STATUS: IMPLEMENTED 2026-08-02.** Single Ubuntu 24.04 image (`Dockerfile`),
> unified `scripts/specc` wrapper (native|image, docker|podman), rewritten
> installers, Windows `install.ps1`/`specc.ps1`, single-image CI. Deleted:
> `Dockerfile.lean`, `scripts/build.sh`, `scripts/docker_build.sh`,
> `scripts/specc.sh`. Verified: image builds (737 MB); full suite **98/0** from
> clean HEAD both natively and in-container; wrapper e2e green in both modes;
> `install-native.sh` end-to-end green. (Working-tree WIP — `pandoc_cli.lua` +
> test edits — showed unrelated intermittent failures; clean HEAD is stable.)

**Two channels, one image, one wrapper:**
1. **Container** — a **single** published image (`ghcr.io/specir/speccompiler:latest`),
   built **on `ubuntu:24.04` only** (no pandoc/core Alpine base, no lean/full split,
   no legacy from-source Dockerfile). Everything included: apt pandoc + extensions +
   deno (charts) + JRE/plantuml/graphviz (puml).
2. **Native** — git clone + `scripts/install-native.sh`, **Ubuntu 24.04 only**.
   Other distros get a **documented manual dependency list** (below) and then run
   `build-extensions.sh` themselves — no per-distro automation.

Confirmed decisions: no version pinning for users (`:latest` always) · unify the
`specc` wrapper (today 3 copies) · add a Windows PowerShell installer/wrapper.

---

## 1. Verification: the zip-extension "linking bug" (2026-08-02)

**Verdict: no bug in the current `build-extensions.sh` on Ubuntu 24.04.** Verified
empirically on this machine (fresh `vendor/` in scratchpad, apt pandoc 3.1.3):

- `zip.so` is correctly linked: `readelf -d` shows `NEEDED libzip.so.4`; `ldd -r`
  fully resolves (only `lua_*` left undefined, resolved by host pandoc at dlopen).
- Functional in-pandoc test: create zip → add entry from string → reopen → `stat`
  — OK, via the same API `src/infra/format/zip_utils.lua` uses.
- Real pipeline: `SPECCOMPILER_DIST=<scratch> ./tests/run.sh ooxml` → **3/3**
  (docx emission = heaviest zip user); `floats` → **5/5** (incl. math/luaamath).

**The bug that was remembered** is the *old* path: brimworks/lua-zip's bundled
`CMakeLists.txt` predates CMake 3.5 and breaks on modern CMake (hit on Alpine).
`build-extensions.sh` already routes around it by compiling `lua_zip.c` directly
with gcc + `pkg-config libzip` (see the comment at its zip step). With Alpine
dropped, the historical trigger disappears entirely.

**Hardening worth one line:** if `libzip-dev`/`pkg-config` are missing, the
`$(pkg-config …)` substitution is silently empty and `gcc -shared` still produces a
`.so` (fails only at runtime). Add a post-build assert:
`readelf -d "$OUT/brimworks/zip.so" | grep -q libzip || exit 1`.

**Side findings (not bugs, worth noting):**
- `libuv1-dev` is **not needed**: luv builds with `-DWITH_SHARED_LIBUV=OFF`
  (bundled libuv; `luv.so` NEEDs only libc). Drop it from `install-native.sh`
  and the dep list.
- The `require("luaamath")` fallback in `math_render_utils.lua:27` can never
  succeed (the .so exports `luaopen_amath`, not `luaopen_luaamath`); production
  always loads via `package.loadlib(path, "luaopen_amath")`. Dead code, harmless.

---

## 2. The single Dockerfile (replaces Dockerfile + Dockerfile.lean)

Base `ubuntu:24.04` ⇒ the image **is** the native install, containerized: same apt
pandoc 3.1.3 (verified floor, full suite 99/0), same glibc extensions from the same
`build-extensions.sh`, same wrapper. One build path to maintain; the Alpine echarts
musl shims and the pandoc-version skew (image 3.8 vs native 3.1) both disappear.

Internal two-stage (build stage compiles extensions; runtime stage stays
toolchain-free) but **one published target/tag**:

    FROM ubuntu:24.04 AS build
    RUN apt-get update && apt-get install -y --no-install-recommends \
        pandoc build-essential cmake pkg-config git curl unzip ca-certificates \
        liblua5.4-dev libsqlite3-dev libzip-dev peg
    COPY scripts/build-extensions.sh scripts/versions.env ./scripts/
    COPY src/tools/ ./src/tools/
    RUN bash scripts/build-extensions.sh /opt/speccompiler/vendor

    FROM ubuntu:24.04
    RUN apt-get update && apt-get install -y --no-install-recommends \
        pandoc libzip4t64 ca-certificates curl \
        default-jre-headless graphviz fonts-dejavu-core   # puml
    # deno: official glibc binary, version from versions.env (no musl shims)
    # plantuml.jar: pinned via versions.env (same as native WITH_PUML)
    COPY --from=build /opt/speccompiler/vendor /opt/speccompiler/vendor
    COPY src/ models/default/ models/sw_docs/ tests/ …
    COPY scripts/specc /usr/local/bin/specc     # the unified wrapper, MODE=native
    ENV SPECCOMPILER_HOME=… LUA_PATH=… LUA_CPATH=… DENO_DIR=…
    WORKDIR /workspace
    ENTRYPOINT ["specc"]

- `tests/` stays in-image so model-overlay images (specc-abnt) keep running their
  suites; `DENO_DIR` convention unchanged.
- CI (`docker-publish.yml`): one build, one `:latest` push (plus `:<sha>` for
  traceability; no user-facing version tags).
- **Retire:** `Dockerfile` (GHC toolchain), `Dockerfile.lean` (both targets),
  `scripts/docker_build.sh`, and `scripts/build.sh` (from-source pandoc no longer
  needed — decision below).

## 3. Native install — Ubuntu-only script + manual list for other distros

`install-native.sh` keeps apt automation (minus `libuv1-dev`); the non-apt branch
just points at the documented list:

**Build dependencies (apt names / generic):**
- `pandoc` ≥ 3.1 — *distro package* linking shared liblua5.4 (never the official
  static release tarball — sealed Lua, extensions cannot load)
- `build-essential` — C toolchain (gcc, make)
- `cmake` — luv build
- `pkg-config` — libzip + Lua detection
- `git`, `curl`, `unzip`, `ca-certificates` — fetch pinned sources
- `liblua5.4-dev` — Lua 5.4 headers
- `libsqlite3-dev` — lsqlite3
- `libzip-dev` — brimworks/zip
- `peg` — leg parser generator for luaamath (*optional* — script builds it from
  source when absent)

**Optional runtime:** `default-jre-headless` (+ pinned plantuml.jar) for puml;
deno (official installer) for charts (model-owned, abnt bootstrap).

Any distro that provides equivalents can run
`bash scripts/build-extensions.sh <vendor-dir>` directly — it is already
pkg-config-driven with sane fallbacks. This list goes in README + manual.

## 4. Wrapper unification (3 → 1)

Today the `pandoc --from markdown --to json --lua-filter filter.lua …` line lives in
the in-image specc (Dockerfile.lean), the install-native heredoc, and behind
`specc.sh`. Replace with **one** `scripts/specc` reading
`~/.config/speccompiler/env`:
- `MODE=native` → set LUA_PATH/CPATH from `SPECCOMPILER_HOME`/`_DIST`, exec pandoc.
  (This is also the copy baked into the image.)
- `MODE=image` → engine detection (`docker` → `podman`; rootless podman uses
  `--userns=keep-id` instead of `-u uid:gid`), lazy-pull `:latest`, run.
Both installers install the same file and only write config.

## 5. Windows PowerShell installer (new)

    irm https://raw.githubusercontent.com/SpecIR/SpecCompiler/main/scripts/install.ps1 | iex

- Detect `docker` → `podman` (check `podman machine` is initialized/running; print
  the exact init/start hint if not).
- Install `specc.ps1` + `specc.cmd` shim (execution-policy-proof, works from cmd
  and PowerShell) into `%LOCALAPPDATA%\SpecCompiler\bin`; append to *user* PATH.
- Run line: mount `"${PWD}:/workspace"`, **no** `-u` (VM handles ownership).
- `.gitattributes`: `*.ps1 text eol=crlf`.
- CI can only lint (PSScriptAnalyzer) — hosted Windows runners can't run Linux
  containers; e2e verification is a manual checklist.

## 6. Implementation order

1. New single `Dockerfile` + simplified `docker-publish.yml` → verify: image builds;
   full suite green in-container; specc-abnt overlay still builds on top.
2. Unified `scripts/specc` (native+image modes, docker/podman) + slim down
   `install.sh` / `install-native.sh` to config-writers; drop `libuv1-dev`; add the
   zip readelf assert → verify: both install modes on this box run the full suite.
3. Delete retired files (`Dockerfile` legacy, `Dockerfile.lean`,
   `docker_build.sh`, `build.sh`) + README/manual rewrite: 3 quickstart blocks
   (Linux container, Windows container, Ubuntu native) + the manual dep list.
4. `install.ps1` / `specc.ps1` / `specc.cmd` → verify: manual run on Windows 11
   with Docker Desktop and with Podman.

## 7. Remaining open decision

- `scripts/build.sh` (591-line from-source toolchain incl. custom pandoc): delete
  outright vs move to an `archive/` branch. Nothing depends on it once the legacy
  Dockerfile goes; recommend delete (git history keeps it).
