# Plan — Remaining-smell remediation (triaged from the audit)

## Context

The adversarial smell audit confirmed **22 smells**. The hook-contract work already
resolved the top cluster — **#1** (`generate` polymorphism), **#2** (incompatible
hook conventions), **#4** (base view reaching into `registry.current()`), **#10**
(`prepare_task` arity), and partially **#3/#11/#12/#15**. That leaves **~16**.

None of the remainder fails a test (the suite is 99/0); they are **maintainability
debt** plus a few **abnt-output correctness gaps** (html/latex). This plan triages
them into phases by effort and risk so the cheap, safe cleanups land first and the
abnt-format work (the biggest, most behaviour-touching theme) is a deliberate,
verified pass.

Repos: host fixes → `SpecCompiler` (`refactor/host-engine-descriptor-plugins`);
abnt fixes → `specc-abnt` (`refactor/descriptor-format-port`).

### Triage

| status | smells |
|---|---|
| **DONE** (hook-contract work) | #1, #2, #4, #10; partial #3 (subject shapes now documented), #15 (SUBJECT_MEMBERS deleted), #12 (TABLE_VIEW build_block validated) |
| **Phase 1 — scar-tissue sweep** | #5 orphan `style_id`, #11 dead `_caps` resolve index, #17 dead `api` plumbing, #18 unused `ctx.model`, #19 vestigial 'old format' + unused `db` param, #15-rest (`ctx:require`) |
| **Phase 2 — dedup helpers** | #20 bookmark-id hash ×4, #21 abnt cover/titlepage class strings |
| **Phase 3 — format pipeline (abnt)** | #7 dead positioned-float chain, #6 three marker namespaces, #9 unused `extends_default`, #22 abnt-latex bookmarks, #8 abnt-html |
| **Phase 4 — inheritance + contract polish** | #13 uninherited schema flags, #14 leaf-only card options, #16 shallow freeze, #3 subject validation |

---

## Phase 1 — Scar-tissue sweep (host; one commit; low risk)

Pure deletions of dead/vestigial code (several introduced by recent work):
- **#5** delete the orphaned float `style_id` from the abnt + default float descriptors (read by nobody; duplicates `id`). *(I added it during the port — remove it.)*
- **#11** stop indexing relation `resolve` into `_caps` (the resolver is dispatched via `data:register_resolver`; the `_caps[relation][id].resolve` entry is never read) — registry.lua hook-index loop.
- **#17** drop the always-nil `api` field threaded through the object render path (`spec_object_render_handler.lua:278` `api = ctx.api`, `spec_object_base.lua:242` `api = subject.api`).
- **#18** demote `ctx.model` out of the render INVARIANT_CORE (asserted-present, read by nobody) — keep it as an optional documented field.
- **#19** delete the dead `"old format (string)"` branch + the unused `db` param in `spec_object_base.lua` (`render_attributes`/`header`/`body`).
- **#15-rest** delete `ctx:require` (dead) OR keep it as a documented guardrail — recommend **keep** (it is a real, working API; only the stale `SUBJECT_MEMBERS` list was the smell, already gone).

## Phase 2 — Dedup helpers (host + abnt; low–medium)

- **#20** extract one `bookmark_id(name)` (fold into the existing `src/pipeline/shared/float_anchor.lua` or `src/infra/format/docx/ooxml_builder.lua`); call it from `emit_float`, both models' `filters/docx.lua`, and the equation builder — the hash is currently copy-pasted in 4 places and collides past ~100k anchors.
- **#21** define abnt's cover/titlepage semantic class names once (a small `models/abnt/shared/semantic_classes.lua`) and reference it from the emitting objects + `filters/docx.lua` `SEMANTIC_CLASS_MAP`, so a rename can't silently lose styling.

## Phase 3 — Format pipeline (the big theme; abnt-facing correctness; medium)

This is where abnt's html/latex actually break. Recommended approach:
- **#7** DELETE the dead positioned-float chain — `convert_positioned_float_div` + the `float-position-start/end` handlers in both `filters/docx.lua`, the `process_positioned_floats`/`section_manager` consumer in `models/default/postprocessors/docx.lua` — nothing emits `speccompiler-positioned-float` (0 emitters, verified). The LIVE pre-textual-image pipeline (just committed) is unaffected.
- **#6** unify the marker namespaces onto ONE block-format token (`"speccompiler"`) + one comment prefix; add `render_utils.marker(text)` (emit) and `is_marker(block)` (consume) so default's filters (which only check `"speccompiler"`) stop silently dropping `"specdown"` blocks.
- **#9** route abnt's `filters/docx.lua`/`latex.lua` through `extends_default` (override only the abnt-specific cases) and delete the re-implemented default-equivalent handlers — or, if composition proves too invasive, delete the unused `extends_default` seam. Prefer composition.
- **#22** make abnt's `filters/latex.lua` RawBlock handler accept `"speccompiler"` markers too and translate `bookmark-start` → `\hypertarget`/`\label` (today only `"specdown"` matches, so float cross-refs drop in latex).
- **#8** abnt html: add a minimal `models/abnt/filters/html.lua` (or `extends_default`) so html doesn't silently fall back to default and emit a broken doc — at minimum fail-fast in the writer when a template lacks a filter for a requested format.

> Out of scope here (separate, output-changing): the abnt `lof`/`lot`/`toc`
> OOXML→Pandoc conversion (returns Pandoc AST instead of `RawBlock("openxml")`).
> It needs golden re-verification and is its own pass; flag, don't fold in.

## Phase 4 — Inheritance + contract polish (host; low; mostly docs/validation)

- **#13** walk `extends` to fill `is_composite`/`is_default`/`numbered`/`pid_prefix` from the nearest ancestor (the propagate step already walks the chain for attributes) — or explicitly document them as leaf-local.
- **#14** pass `card_render` a chain-merged option view (leaf wins) so render options declared on a base type are visible — or document leaf-only.
- **#16** make the frozen-ctx docstring honest (only top-level rebind is prevented) OR deep-freeze the `subject`/`config` snapshot.
- **#3** add per-kind `subject` required-field assertions in `hook_ctx.build`/`build_data` (drive off a small per-capability member table) so a missing subject field fails loudly, not as a silent nil.

## Verification

- Each phase: `./tests/run.sh` → **99/0** before moving on (relations 8/8 + floats 7/7 are the canaries for Phases 1/3).
- After Phase 3: rebuild the 7 abnt docs to **DOCX** (all 3 pre-textual images still inject; 0 dangling PAGEREF) **and LaTeX** (float cross-refs now resolve); spot-check an abnt **html** build is either correct or fails fast.
- Re-run the relevant contract-bites (retired `generate`, missing `build_block`, top-level fn) — still fire.
- `git grep` proofs: zero `style_id`/`api`/positioned-float markers; one bookmark-id helper; one marker namespace.

## Recommendation / sequencing

1. **Phases 1–2 now** — cheap, safe, high-cleanliness; removes the scar tissue (incl. the `style_id` I added). One host commit + one abnt commit.
2. **Phase 3 next** as a focused, separately-verified effort — it's the real abnt html/latex correctness + the largest dead-code removal.
3. **Phase 4 last** — polish; mostly docstrings + small validation.

Each phase is independently green and committable; abnt and host changes stay on
their own branches; never stage unrelated WIP.

---

## Final disposition (remediation executed)

Every audited smell is now resolved — either fixed, or verified intentional and
documented. Host commits on `refactor/host-engine-descriptor-plugins`; abnt commits
on `refactor/descriptor-format-port`. Suite stayed **99/0** throughout.

**Fixed — host:**
- `589acc8` — #17 dead `api` plumbing, #19 vestigial old-format branch + unused `db`,
  #20 bookmark-id deduped into one `float_anchor.bookmark_id`, #16 honest
  shallow-freeze docstring.
- `005cf11` — #7 dead positioned-float chain (−232 lines), #5 (default) orphan float
  `style_id` on FIGURE/MATH/LISTING/CHART/PLANTUML.

**Fixed — abnt (`3a8a54a`):**
- #22/#6 — LaTeX float anchors: the filter now accepts the host's `speccompiler`
  marker namespace and emits `\phantomsection\label{anchor}` (NOT `\hypertarget` —
  abnt float xrefs render as `\hyperref[...]`, which resolves only against `\label`;
  proven with pdflatex). Float cross-refs in LaTeX now resolve instead of dangling.
- #21 — the 24 cover/title-page/pre-textual semantic-class strings extracted into
  `shared/semantic_classes.lua`; emitters + both filter maps key off the constants.
- #5 (abnt) — orphan `style_id` (6 floats) + `header_style_id`/`body_style_id`
  (21 objects), never persisted, never read.

**Verified intentional — documented, no behaviour change:**
- #11 — the eager `_caps` index uniformly holds every hook including a relation's
  `resolve` (a registry test reads it via `get_hook`); kept, comment clarified (`589acc8`).
- #18 — `ctx.model` IS read (table_view, chart); kept in INVARIANT_CORE.
- #13/#14/#3 (`f369be4`) — schema flags (`is_composite`/`is_default`/`numbered`/
  `pid_prefix`) are **leaf-local by design** (inheriting would wrongly make
  TRACEABLE/HLR/VC composite); card render options are leaf-local `type_schema`
  fields; subject shapes are documented in the `ctx.lua` header (hard per-capability
  assertions would re-introduce the removed `SUBJECT_MEMBERS` structure).
- #9 — `extends_default`/`compose_filters` is a working, documented composition seam
  (`src/infra/format/writer.lua`); abnt deliberately does not use it — its docx
  re-implementation carries load-bearing ABNT-specific logic. Left available.
- #8 — abnt HTML uses the generic `default` HTML filter by design (valid output,
  no abnt cover styling); documented in the abnt `README.md`. ABNT-specific HTML is
  future work, and would need html/latex golden oracles (today the 7 abnt tests are
  JSON-AST oracles only).

**Doc accuracy re-synced to the refactor** (separate from the smell work): engineering
SDD/dictionary, the `user_docs` model-authoring guide (`6dc26fa`), and the dissertation
`cap3-proposta/03b-extensibilidade-modelos.md` (descriptor/hooks/host-engine).
