#!/bin/bash
# SpecCompiler Mutation Testing Runner
# Usage: ./tests/mutation/mutate.sh [options]
#
# Options:
#   --sql                Run SQL proof view mutations
#   --lua <file>         Run Lua source mutations on a specific file
#   --all                Run all mutation modes
#   --verbose            Show killed mutants (not just survivors)
#   --help               Show this help

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Set environment (matching bin/speccompiler and tests/run.sh)
export SPECCOMPILER_HOME="$PROJECT_ROOT"
export SPECCOMPILER_DIST="${SPECCOMPILER_DIST:-${PROJECT_ROOT}/dist}"
DIST_DIR="$SPECCOMPILER_DIST"
PANDOC_CMD="${DIST_DIR}/bin/pandoc"
if [ ! -x "$PANDOC_CMD" ]; then
    PANDOC_CMD="pandoc"
fi
export LUA_PATH="${SPECCOMPILER_HOME}/src/?.lua;${SPECCOMPILER_HOME}/src/?/init.lua;${SPECCOMPILER_HOME}/?.lua;${SPECCOMPILER_HOME}/?/init.lua;${DIST_DIR}/vendor/?.lua;${DIST_DIR}/vendor/?/init.lua;${DIST_DIR}/vendor/slaxml/?.lua;${SPECCOMPILER_HOME}/tests/?.lua;${SPECCOMPILER_HOME}/tests/?/init.lua;${SPECCOMPILER_HOME}/tests/mutation/?.lua;${LUA_PATH:-}"
export LUA_CPATH="${DIST_DIR}/vendor/?.so;${DIST_DIR}/vendor/?/?.so;${LUA_CPATH:-}"
export PATH="${DIST_DIR}/bin:${PATH}"

# Parse arguments
MODE=""
TARGET=""
VERBOSE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --sql)
            MODE="sql"
            shift
            ;;
        --lua)
            MODE="lua"
            shift
            TARGET="$1"
            shift
            ;;
        --all)
            MODE="all"
            shift
            ;;
        --verbose|-v)
            VERBOSE="--metadata verbose=true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --sql                Run SQL proof view mutations"
            echo "  --lua <file>         Run Lua source mutations on a specific file"
            echo "  --all                Run all mutation modes (requires --lua target for Lua mode)"
            echo "  --verbose, -v        Show killed mutants (not just survivors)"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --sql"
            echo "  $0 --lua src/pipeline/shared/render_utils.lua"
            echo "  $0 --sql --verbose"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run $0 --help for usage"
            exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "No mode specified. Use --sql, --lua <file>, or --all"
    echo "Run $0 --help for usage"
    exit 1
fi

cd "$PROJECT_ROOT"

# Ensure report directory exists
mkdir -p tests/reports/mutation

# Safety: if Lua mode is interrupted, restore the original source file.
# The mutator writes a .bak file before the first mutation and restores on
# normal exit, but SIGINT/SIGTERM/SIGABRT could leave the source corrupted.
MUTATION_BACKUP=""
if [[ "$MODE" == "lua" || "$MODE" == "all" ]] && [[ -n "$TARGET" ]]; then
    if [[ -f "$TARGET" ]]; then
        MUTATION_BACKUP="${TARGET}.mutation_backup"
        cp "$TARGET" "$MUTATION_BACKUP"
    fi
fi

cleanup_mutation_backup() {
    if [[ -n "$MUTATION_BACKUP" && -f "$MUTATION_BACKUP" ]]; then
        # Restore original if the source was left in a mutated state
        if ! diff -q "$TARGET" "$MUTATION_BACKUP" > /dev/null 2>&1; then
            echo ""
            echo "WARNING: Restoring $TARGET from backup (interrupted during mutation)"
            cp "$MUTATION_BACKUP" "$TARGET"
        fi
        rm -f "$MUTATION_BACKUP"
    fi
}
trap cleanup_mutation_backup EXIT INT TERM

# Build metadata flags
META_FLAGS="--metadata mode=$MODE"
if [[ -n "$TARGET" ]]; then
    META_FLAGS="$META_FLAGS --metadata target=$TARGET"
fi

# Run the mutation engine (|| true: ignore Pandoc libuv teardown abort)
"$PANDOC_CMD" --lua-filter tests/mutation/mutator.lua \
    $META_FLAGS \
    $VERBOSE \
    < /dev/null || true

# Cleanup backup (normal exit — source already restored by mutator.lua)
cleanup_mutation_backup
