# Mutation Testing Framework

Mutation testing for SpecCompiler's SQL proof views and Lua pipeline source.
Measures test suite effectiveness by injecting faults and checking if tests detect them.

## Quick Start

```bash
# SQL proof view mutations (safe, in-memory — ~5 min)
./tests/mutation/mutate.sh --sql

# Lua source mutations on a specific file (~2-10 min depending on file size)
./tests/mutation/mutate.sh --lua src/pipeline/verify/verify_handler.lua

# Verbose: show killed mutants too (not just survivors)
./tests/mutation/mutate.sh --sql --verbose
```

Reports are written to `tests/reports/mutation/sql_report.json` and `lua_report.json`.

## How It Works

### SQL Mode (`--sql`)

Mutates SQL proof view definitions **in-memory** (never writes to disk). For each of the
26 proof views (17 default + 9 sw_docs), applies single-site mutations and checks if the
verify/casting_negative test suites detect the change via diagnostic code comparison.

**Operators** (6): negate EXISTS, relax AND→OR, flip comparisons, swap NULL checks,
shift HAVING thresholds, drop WHERE predicates.

**Oracle**: Compares exact diagnostic error/warning code counts against baseline.

### Lua Mode (`--lua <file>`)

Mutates a Lua source file **on disk** (writes mutated file, runs tests, restores original).
A shell trap + backup file protects against interrupted mutations leaving corrupted source.

**Operators** (10): flip equality/order/logic/bool, remove not, nil→false, flip return,
off-by-one, boundary shift, empty string.

**Oracle** (triple-signal): Any change in (1) output file content, (2) diagnostic codes,
or (3) pipeline pass/fail status kills the mutant. Mutations are pre-validated with
`load()` to skip syntactically invalid mutants.

## Architecture

```
tests/mutation/
  mutate.sh           Shell entry point (env setup, safety trap, argument parsing)
  mutator.lua         Pandoc filter: orchestrates baseline, mutation, comparison
  sql_operators.lua   SQL mutation operator catalog (6 operators)
  lua_operators.lua   Lua mutation operator catalog (10 operators)
```

The engine runs as a Pandoc Lua filter (`pandoc --lua-filter tests/mutation/mutator.lua`)
to reuse the same Lua/Pandoc runtime as the SpecCompiler pipeline. This enables in-process
execution via `engine.run_project()` without subprocess overhead.

## Safety

- **SQL mode**: Mutations are injected into `package.loaded` (Lua module cache). No files
  are written. Safe to run anywhere, anytime.
- **Lua mode**: Mutates the source file on disk. Protected by:
  1. `mutate.sh` creates a `.mutation_backup` file before starting
  2. A shell `trap` on EXIT/INT/TERM restores from backup if the source was left mutated
  3. `mutator.lua` restores the original source after the mutation loop completes
- **Normal test suite**: The mutation framework is completely isolated. `tests/run.sh`
  never discovers or invokes it. It must be run explicitly via `mutate.sh`.

## Interpreting Results

- **100% kill rate**: Every mutation was detected. The test suite is strong for this code.
- **Survivors**: Mutations the tests didn't catch. Each survivor is either:
  - A **test gap**: real weakness — add a test that exercises this code path
  - An **equivalent mutant**: the mutation doesn't change observable behavior
    (e.g., `nil → false` when callers only check truthiness)
- **Kill signals** (Lua mode): Reports which signal detected each mutant:
  - `output`: the generated document changed (most common for pipeline code)
  - `diagnostics`: error/warning codes changed (common for verify/validation code)
  - `status`: the pipeline crashed (rare but definitive)
