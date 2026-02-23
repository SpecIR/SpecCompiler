# Tool Operational Requirements -- SpecCompiler Test Framework

| Field | Value |
|---|---|
| Document ID | TOR-STF-001 |
| Revision | Draft A |
| Date | 2026-02-07 |
| Tool Name | SpecCompiler Test Framework |
| Scope | E2E, model suites, reports, coverage |

## 1. Purpose and Scope

This document defines operational requirements for the SpecCompiler test framework implemented by `tests/run.sh`, `tests/runner.lua`, and `tests/helpers/*`.

In scope:
- Markdown-driven E2E tests under `tests/e2e/*`.
- Model-owned test suites under `models/*/tests`.
- Oracle execution (`.lua`, `.docx`, `.html`, `.md` expected artifacts).
- JUnit and coverage report generation.

Out of scope:
- Core SpecCompiler functional requirements (covered by `docs/plans/TOR-speccompiler-core.md`).

## 2. Tool Overview

The framework executes test cases by running SpecCompiler in-process through `core.engine`, then comparing generated outputs against expected artifacts and/or Lua oracles.

Primary entry points:
- Host runner: `tests/run.sh`
- Test executor/filter: `tests/runner.lua`
- Reporting helpers: `tests/helpers/coverage.lua`, `tests/helpers/junit_reporter.lua`, `tests/helpers/html_report.lua`

## 3. Operational Requirements

### 3.1 Discovery and Selection

**TOR-STF-001:** The framework shall discover E2E suites from `tests/e2e/*` where `suite.yaml` exists.

**TOR-STF-002:** The framework shall discover model-owned suites from `models/*/tests` where `suite.yaml` exists and expose them as `<model>-tests`.

**TOR-STF-003:** The framework shall support running all suites, a single suite, or a single test case (`suite/test`) from CLI.

### 3.2 Test Case Contract

**TOR-STF-004:** Each test case shall be authored as Markdown input (`*.md`) with a matching expected artifact in `expected/`.

**TOR-STF-005:** Supported oracle/artifact extensions shall be `.lua`, `.docx`, `.html`, `.md`.

**TOR-STF-006:** For `.lua` oracles, the framework shall render JSON output and invoke an assertion function exported by the oracle.

**TOR-STF-007:** Suite-level `expect_errors: true` shall enable negative testing by passing diagnostics to Lua oracles without requiring output generation.

**TOR-STF-008:** For non-Lua expected artifacts, comparison shall be byte-for-byte unless suite logic explicitly uses semantic comparators.

### 3.3 Execution Behavior

**TOR-STF-009:** The framework shall run SpecCompiler in-process via `core.engine.run_project`.

**TOR-STF-010:** The framework shall create test-local build outputs under `<suite>/build/`.

**TOR-STF-011:** The framework shall remove transient suite-local `specir.db` after each test execution.

**TOR-STF-012:** The framework shall return non-zero process exit when one or more tests fail.

### 3.4 Reporting

**TOR-STF-013:** The framework shall print per-suite and aggregate pass/fail/skip counts.

**TOR-STF-014:** When enabled (`--junit`), the framework shall generate JUnit XML under `tests/reports/junit.xml`.

**TOR-STF-015:** When enabled (`--coverage`), the framework shall produce per-suite LCOV reports under `tests/reports/coverage/*.lcov`.

**TOR-STF-016:** Coverage mode shall merge suite LCOV files into `tests/reports/coverage/merged.lcov`.

**TOR-STF-017:** Coverage mode shall generate HTML coverage output in `tests/reports/coverage/html/*`, with merged index at `tests/reports/coverage/html/merged/index.html`.

### 3.5 Coverage Accounting Policy

**TOR-STF-018:** Coverage accounting shall exclude blank lines, comment-only lines, standalone `end`, and standalone `else` lines.

**TOR-STF-019:** If source files are missing during LCOV normalization, coverage accounting shall default to legacy line inclusion behavior.

### 3.6 Fixture and Ownership Policy

**TOR-STF-020:** Preset/type/model behavior tests shall use fixture files on disk under existing models (default-first), using clearly namespaced paths (for example `models/default/types/views/test_fixtures/*`, `models/default/styles/test_*`) rather than generating ad-hoc runtime model trees in oracles.

**TOR-STF-021:** Model-specific behavior tests shall be hosted under the corresponding model’s `models/<model>/tests` when the primary coverage target is model code.

**TOR-STF-022:** Core-engine behavior tests shall remain under `tests/e2e/*` when the primary coverage target is `src/*`.

### 3.7 Traceability Policy

**TOR-STF-023:** Each suite shall include VC mapping comments in `suite.yaml`.

**TOR-STF-024:** Each test file name shall follow `vc_*` convention and map to a verification case (VC).

**TOR-STF-025:** VCs shall trace to HLRs (and LLRs when present) in release documentation.

## 4. Environment Requirements

Required runtime:
- Bash
- Pandoc
- Lua 5.4 runtime and required Lua modules (`dkjson`, luacov for coverage mode)
- Optional reporting tools: `lcov`/`genhtml` (Lua HTML fallback available)

## 5. Known Constraints

- Exact-byte comparisons for non-Lua expected artifacts can be sensitive to formatting drift.
- Environment-specific capabilities (for example chart rendering) may mark tests as skipped.
- Coverage percentages depend on available report tooling and configured line-filter policy.

## 6. Acceptance Criteria

A compliant framework execution shall:
1. Discover configured suites (core and model-owned).
2. Execute Markdown-driven tests with expected artifacts.
3. Produce deterministic pass/fail/skip summary.
4. Emit JUnit and coverage artifacts when requested.
5. Preserve explicit ownership boundaries between core and model coverage.
