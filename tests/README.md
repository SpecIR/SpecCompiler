# SpecCompiler Test Framework

Quick-start guide. For detailed requirements and instructions for creating tests, see:

- [Tool Operational Requirements (TOR)](../docs/engineering_docs/plans/TOR-speccompiler-test-framework.md)
- [Tool User Manual (TUM)](../docs/engineering_docs/plans/TUM-speccompiler-test-framework.md)

## Running Tests

```bash
# All suites
./tests/run.sh

# Single suite
./tests/run.sh verify

# Single test
./tests/run.sh verify/vc_018_03_verify_floats

# With coverage
./tests/run.sh --coverage

# With JUnit XML
./tests/run.sh --junit

# Via Docker (same interface)
./tests/docker-run.sh [same arguments as run.sh]
```

## Directory Layout

```
tests/
  run.sh              Host entry point
  docker-run.sh       Docker wrapper (same CLI as run.sh)
  runner.lua           Pandoc filter test executor
  e2e/                 18 E2E suites (each has suite.yaml + vc_*.md + expected/)
  fixtures/            Shared test data
  helpers/             Lua helpers (ast_compare, coverage, db_helpers, ...)
  mutation/            Mutation testing framework (see mutation/README.md)
  reports/             Generated: junit.xml, coverage/, mutation/
```

Model-owned suites live under `models/<model>/tests/` and are discovered
as `<model>-tests` (e.g., `sw_docs-tests`).

## How It Works

Each test is a CommonSpec Markdown file (`.md`) that gets processed by the full
SpecCompiler pipeline in-process via `core.engine.run_project()`. The generated
output (a Pandoc AST in JSON format) is then compared against an expected
artifact — typically a Lua oracle.

```
  vc_013_02_syntax_parsing.md          expected/vc_013_02_syntax_parsing.lua
  ┌─────────────────────────┐          ┌──────────────────────────────────┐
  │ # Requirements @SRS-001 │  engine  │ return function(actual_doc,      │
  │ ## Auth @HLR-AUTH-001   │ ──────►  │                helpers)          │
  │ > priority: High        │  (JSON)  │   ...compare AST...             │
  │ ...                     │          │   return pass, err               │
  └─────────────────────────┘          └──────────────────────────────────┘
       test input                           Lua oracle
```

**Lua oracles** receive the generated Pandoc AST and a `helpers` table, and
return `true` on pass or `false, "message"` on failure:

```lua
return function(actual_doc, helpers)
    -- Build expected AST, compare against actual_doc
    return helpers.assert_ast_equal(actual_doc, expected, helpers.options)
end
```

**Negative tests** (`expect_errors: true` in `suite.yaml`) skip output
generation and instead verify that expected diagnostic codes were raised:

```lua
return function(actual_doc, helpers)
    -- actual_doc is nil; check helpers.diagnostics instead
    local diag = helpers.diagnostics
    -- assert expected error codes are present
    return true
end
```

Other oracle types (`.docx`, `.html`, `.md`) use byte-for-byte file comparison.

## Writing Tests

See [TUM Section 5](../docs/engineering_docs/plans/TUM-speccompiler-test-framework.md#5-writing-a-new-test) for the full authoring guide.

Short version:

1. Add `vc_<topic>_<id>.md` to `tests/e2e/<suite>/`
2. Add expected artifact in `tests/e2e/<suite>/expected/`
3. Register VC mapping in `suite.yaml`
4. Run the suite to verify

## Mutation Testing

Separate framework for measuring test suite effectiveness. See
[mutation/README.md](mutation/README.md) for full details.

```bash
# SQL proof view mutations (in-memory, safe)
./tests/mutation/mutate.sh --sql

# Lua source mutations (on-disk with safety backup)
./tests/mutation/mutate.sh --lua src/pipeline/verify/verify_handler.lua
```

Reports: `tests/reports/mutation/sql_report.json`, `tests/reports/mutation/lua_report.json`.
