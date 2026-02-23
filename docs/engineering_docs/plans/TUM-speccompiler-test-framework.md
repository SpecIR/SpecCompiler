# Tool User Manual -- SpecCompiler Test Framework

| Field | Value |
|---|---|
| Document ID | TUM-STF-001 |
| Revision | Draft A |
| Date | 2026-02-07 |
| Tool Name | SpecCompiler Test Framework |

## 1. Purpose

This manual explains how to run, extend, and maintain the SpecCompiler test framework used by `tests/run.sh` and `tests/runner.lua`.

## 2. Directory Layout

- Core E2E suites: `tests/e2e/<suite>/`
- Core expected artifacts: `tests/e2e/<suite>/expected/`
- Model-owned suites: `models/<model>/tests/`
- Reports: `tests/reports/`
- Coverage reports: `tests/reports/coverage/`

Each suite contains:
- `suite.yaml`
- One or more `vc_*.md` test inputs
- Matching expected artifacts in `expected/`

## 3. Running Tests

From repository root:

```bash
./tests/run.sh
```

Run single suite:

```bash
./tests/run.sh verify
```

Run single test:

```bash
./tests/run.sh verify/vc_verify_003_relations
```

Run with coverage:

```bash
./tests/run.sh --coverage
```

Run with JUnit output:

```bash
./tests/run.sh --junit
```

## 4. Coverage Reports

Coverage outputs:
- Per-suite LCOV: `tests/reports/coverage/<suite>.lcov`
- Merged LCOV: `tests/reports/coverage/merged.lcov`
- Merged HTML: `tests/reports/coverage/html/merged/index.html`

Coverage line policy excludes:
- blank lines
- comment-only lines
- standalone `end`
- standalone `else`

## 5. Writing a New Test

### 5.1 Core behavior (`src/*` target)

1. Add Markdown input: `tests/e2e/<suite>/vc_<topic>_<id>.md`
2. Add expected artifact under `tests/e2e/<suite>/expected/`
3. Register VC mapping in `tests/e2e/<suite>/suite.yaml`
4. Run target suite and full suite

### 5.2 Model behavior (`models/*` target)

If the primary coverage target is model code, add the test in:
- `models/<model>/tests/`

Do not place model-focused tests in core suites unless the core behavior is the intended target.

## 6. Oracle Types

Supported expected artifact types:
- `.lua`: custom assertion function (preferred for complex AST/diagnostic checks)
- `.docx`, `.html`, `.md`: direct file comparison

Lua oracle contract:

```lua
return function(actual_doc, helpers)
  -- return true on pass
  -- return false, "message" on failure
end
```

For negative tests (`expect_errors: true` in `suite.yaml`), diagnostics are passed via `helpers.diagnostics`.

## 7. Preset/Fixture Policy

For preset/type loading coverage:
- Prefer fixtures under existing models (default-first), using clearly namespaced paths:
  - Presets: `models/default/styles/test_*`
  - Views: `models/default/types/views/test_fixtures/*`
  - Types: add dedicated test types (non-default) under `models/default/types/*` when needed
- Avoid building ad-hoc model/preset trees dynamically inside oracles except for temporary probing during debugging.
- Keep fixture models minimal and documented.

## 8. VC to HLR/LLR Traceability

Required traceability chain for release:
1. Test case (`vc_*`) -> VC entry in `suite.yaml`
2. VC -> HLR reference in release docs (`docs/requirements/*`, `docs/verification/*`)
3. HLR -> LLR (when LLR set exists)

Recommended practice:
- Keep a per-suite trace table in comments of `suite.yaml`.
- Use stable IDs in markdown titles and/or metadata.
- Add missing LLRs before expanding broad test volume.

## 9. Troubleshooting

Common checks:

```bash
# Re-run a failing suite
./tests/run.sh <suite>

# Rebuild full coverage artifacts
./tests/run.sh --coverage

# Inspect merged coverage report
xdg-open tests/reports/coverage/html/merged/index.html 2>/dev/null || true
```

If coverage seems stale:
- confirm `tests/reports/coverage/` was regenerated
- verify merged LCOV timestamp changed
- rerun with no interrupted jobs

## 10. Governance Updates

When framework behavior changes:
1. Update this TUM.
2. Update `docs/plans/TOR-speccompiler-test-framework.md`.
3. Update suite policies where needed (`suite.yaml` comments and ownership).
