# Figure Image Copy — Design

**Date:** 2026-08-02
**Goal:** Make the FIGURE float behave like PLANTUML: materialize its image
under the build directory at a canonical path, so every assembled output
(docx, html, latex, markdown) references images the same way.

## Problem

`models/default/types/floats/figure.lua` resolves the image path relative to
the source file (`from_file`) and stores that *source-tree* path in
`resolved_ast`. The assembled document therefore references files scattered
across the source tree — broken when the output is moved, and inconsistent
with PLANTUML/CHART which reference `diagrams/<hash>.png` relative to
`build_dir` (docx emits with `--resource-path=<build_dir>`; html/latex
outputs live inside `build_dir`).

## Design

### Canonical path

`<build_dir>/images/<sha1(file-content)><ext>`, stored in `resolved_ast` as
the build-relative path `images/<sha1><ext>` (same convention as PLANTUML's
`diagrams/<hash>.png`).

Content-addressed naming gives:

- **Copy only when needed** — if the destination exists, its bytes are by
  construction identical; skip the write (same skip-if-output-exists caching
  as `external_render_handler`).
- **Dedup** — the same image referenced from N source files is copied once.
- **Canonical rewriting** — any emitter can rely on `images/…` relative to
  the assembled document.

### Data flow change

The internal-transform hook context (`dctx.subject`) gains `build_dir`,
threaded exactly like `external_render_handler` does for `prepare_task`:

- `spec_floats.lua`: `FloatResolver.new(data, log, diagnostics, build_dir)`
  (from `ctx.build_dir`), and `resolve_internal` puts `build_dir` in the
  dctx subject.

`from_file` is already selected by the pending-floats query; no schema or
query change is required.

### figure.lua transform

1. Trim raw path; empty → warn, return nil (unchanged).
2. Resolve relative to `from_file` (unchanged helper).
3. Read the file (binary). On success:
   - sha1 the content (`pandoc.sha1`, plain-Lua fallback as in plantuml.lua);
   - `ensure_dir(<build_dir>/images)`; write `<hash><ext>` only if absent;
   - emit `png_path = "images/<hash><ext>"`.
4. Fallback — source unreadable or no `build_dir` in context: warn and store
   the resolved source path (today's behavior). This keeps every existing
   test green (they all reference nonexistent dummy images) and degrades
   gracefully.

### Known limitations (parity with PLANTUML)

- Editing an image without touching the referencing markdown does not
  re-resolve the float (spec-level cache); a rebuild after the md changes or
  a clean build picks it up.
- Wiping `build_dir` while keeping `specir.db` leaves resolved floats
  pointing at not-yet-recopied files (same as PLANTUML diagrams).

## Tests

- **Unit** `tests/figure_copy_test.lua` (standalone, `dist/bin/lua5.4`):
  deep-tree relative resolution, copy on first transform, no-recopy when
  destination exists (sentinel-overwrite check), missing-file fallback.
- **E2E** `tests/e2e/floats/vc_014_05_figure_copy.md` + oracle + real PNG
  fixture under `tests/e2e/floats/assets/`: full pipeline; asserts the AST
  Image target matches `images/<sha1>.png` and the copied file's bytes equal
  the fixture's.
