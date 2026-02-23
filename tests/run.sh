#!/bin/bash
# SpecCompiler E2E Test Runner (Host)
# Usage: ./run.sh [suite] [test] [options]
#
# Examples:
#   ./run.sh                      # Run all suites
#   ./run.sh floats               # Run floats suite
#   ./run.sh floats/csv_table     # Run single test
#   ./run.sh --coverage           # With coverage (per-suite reports + merged)
#   ./run.sh --junit              # With JUnit XML

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Set environment (matching bin/speccompiler)
export SPECCOMPILER_HOME="$PROJECT_ROOT"
export SPECCOMPILER_DIST="${SPECCOMPILER_DIST:-${PROJECT_ROOT}/dist}"
DIST_DIR="$SPECCOMPILER_DIST"
PANDOC_CMD="${DIST_DIR}/bin/pandoc"
if [ ! -x "$PANDOC_CMD" ]; then
    PANDOC_CMD="pandoc"
fi
export LUA_PATH="${SPECCOMPILER_HOME}/src/?.lua;${SPECCOMPILER_HOME}/src/?/init.lua;${SPECCOMPILER_HOME}/?.lua;${SPECCOMPILER_HOME}/?/init.lua;${DIST_DIR}/vendor/?.lua;${DIST_DIR}/vendor/?/init.lua;${DIST_DIR}/vendor/slaxml/?.lua;${SPECCOMPILER_HOME}/tests/?.lua;${SPECCOMPILER_HOME}/tests/?/init.lua;${LUA_PATH:-}"
export LUA_CPATH="${DIST_DIR}/vendor/?.so;${DIST_DIR}/vendor/?/?.so;${LUA_CPATH:-}"

# Parse arguments
SUITE=""
TEST=""
COVERAGE=""
JUNIT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --coverage|-c)
            COVERAGE="true"
            shift
            ;;
        --junit|-j)
            JUNIT="--metadata junit=true"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [suite] [test] [options]"
            echo ""
            echo "Options:"
            echo "  --coverage, -c    Enable coverage reporting (per-suite + merged)"
            echo "  --junit, -j       Enable JUnit XML output"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                      Run all suites"
            echo "  $0 floats               Run floats suite"
            echo "  $0 floats/csv_table     Run single test"
            exit 0
            ;;
        */*)
            # suite/test format
            SUITE=$(echo "$1" | cut -d'/' -f1)
            TEST=$(echo "$1" | cut -d'/' -f2)
            shift
            ;;
        *)
            # Just suite name
            SUITE="$1"
            shift
            ;;
    esac
done

cd "$PROJECT_ROOT"

# Clean stale JUnit partial file so multi-process accumulation starts fresh
if [[ -n "$JUNIT" ]]; then
    rm -f "$PROJECT_ROOT/tests/reports/junit.partial"
fi

# Run a single suite
run_suite() {
    local suite_name="$1"
    local coverage_flag=""

    if [[ -n "$COVERAGE" ]]; then
        coverage_flag="--metadata coverage=true"
    fi

    local test_filter=""
    if [[ -n "$TEST" ]]; then
        test_filter="--metadata test=$TEST"
    fi

    "$PANDOC_CMD" --lua-filter tests/runner.lua \
        --metadata suite="$suite_name" \
        $test_filter \
        $coverage_flag \
        $JUNIT \
        < /dev/null
}

# Get list of suites
get_suites() {
    {
        find tests/e2e -maxdepth 1 -mindepth 1 -type d 2>/dev/null \
            | sort \
            | while read -r suite_dir; do basename "$suite_dir"; done

        find models -maxdepth 3 -type f -path "*/tests/suite.yaml" 2>/dev/null \
            | sort \
            | while read -r suite_yaml; do
                model_dir="$(dirname "$(dirname "$suite_yaml")")"
                model_name="$(basename "$model_dir")"
                echo "${model_name}-tests"
            done
    } | awk 'NF' | sort -u
}

# Sanitize suite name to match coverage helper output naming
suite_to_safe_name() {
    echo "$1" | sed -e 's#[/\\]#_#g' -e 's/[[:space:]]\+/_/g' -e 's/[^[:alnum:]_-]//g'
}

# Reset coverage outputs to avoid stale/moved file pollution
prepare_coverage_dir() {
    local report_dir="tests/reports/coverage"
    rm -rf "$report_dir"
    mkdir -p "$report_dir"
}

# Merge LCOV files for the suites that ran in this invocation
merge_lcov_files() {
    local report_dir="tests/reports/coverage"
    local -a lcov_files=()

    for suite_name in "$@"; do
        local safe_name
        safe_name="$(suite_to_safe_name "$suite_name")"
        local lcov_path="$report_dir/$safe_name.lcov"
        if [[ -f "$lcov_path" ]]; then
            lcov_files+=("$lcov_path")
        fi
    done

    if [[ ${#lcov_files[@]} -eq 0 ]]; then
        return
    fi

    local count="${#lcov_files[@]}"

    if [[ $count -gt 1 ]]; then
        echo ""
        echo "[coverage] Merging $count suite reports..."
        if command -v lcov &> /dev/null; then
            local merged_tmp="$report_dir/.merged.tmp.lcov"
            local next_tmp="$report_dir/.merged.next.lcov"

            cp "${lcov_files[0]}" "$merged_tmp"

            for ((i = 1; i < count; i++)); do
                if ! lcov -a "$merged_tmp" -a "${lcov_files[$i]}" -o "$next_tmp" --quiet &> /dev/null; then
                    echo "  [coverage] Warning: lcov merge failed, falling back to concatenation"
                    cat "${lcov_files[@]}" > "$report_dir/merged.lcov"
                    rm -f "$merged_tmp" "$next_tmp"
                    break
                fi
                mv "$next_tmp" "$merged_tmp"
            done

            if [[ -f "$merged_tmp" ]]; then
                mv "$merged_tmp" "$report_dir/merged.lcov"
            fi
            rm -f "$next_tmp"
        else
            cat "${lcov_files[@]}" > "$report_dir/merged.lcov"
        fi

        echo "  Merged LCOV: $report_dir/merged.lcov"

        # Generate merged HTML report (prefer genhtml, fallback to Lua summary)
        if command -v genhtml &> /dev/null; then
            mkdir -p "$report_dir/html/merged"
            genhtml "$report_dir/merged.lcov" \
                --output-directory "$report_dir/html/merged" \
                --title "SpecCompiler E2E Coverage (All Suites)" \
                --legend \
                --ignore-errors empty \
                --quiet 2>/dev/null || true
            if [[ -f "$report_dir/html/merged/index.html" ]]; then
                echo "  Merged HTML: $report_dir/html/merged/index.html"
            fi
        elif command -v lua5.4 &> /dev/null; then
            mkdir -p "$report_dir/html/merged"
            if lua5.4 -e "package.path='./tests/helpers/?.lua;' .. package.path; local html=require('html_report'); os.exit(html.generate('$report_dir/merged.lcov', '$report_dir/html/merged', 'SpecCompiler E2E Coverage (All Suites)') and 0 or 1)"; then
                echo "  Merged HTML: $report_dir/html/merged/index.html (Lua fallback)"
            else
                echo "  [coverage] Warning: failed to generate merged HTML fallback report"
            fi
        else
            echo "  [coverage] Warning: neither genhtml nor lua5.4 available for merged HTML generation"
        fi
    fi
}

# Main execution
if [[ -n "$SUITE" ]]; then
    # Run specific suite
    run_suite "$SUITE"
elif [[ -n "$COVERAGE" ]]; then
    # With coverage: run each suite in separate process for isolated coverage
    prepare_coverage_dir

    echo "SpecCompiler E2E Test Runner (Coverage Mode)"
    echo "========================================"
    echo ""

    TOTAL_PASSED=0
    TOTAL_FAILED=0
    TOTAL_SKIPPED=0
    COVERAGE_SUITES=()

    for suite in $(get_suites); do
        echo "Running suite: $suite"
        echo "----------------------------------------"

        # Run suite and capture output
        set +e
        output=$(run_suite "$suite" 2>&1)
        exit_code=$?
        set -e

        echo "$output"

        # Extract counts from output
        if [[ "$output" =~ Results:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed,\ ([0-9]+)\ skipped ]]; then
            TOTAL_PASSED=$((TOTAL_PASSED + ${BASH_REMATCH[1]}))
            TOTAL_FAILED=$((TOTAL_FAILED + ${BASH_REMATCH[2]}))
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + ${BASH_REMATCH[3]}))
            COVERAGE_SUITES+=("$suite")
        fi

        echo ""
    done

    echo "========================================"
    echo "TOTAL: $TOTAL_PASSED passed, $TOTAL_FAILED failed, $TOTAL_SKIPPED skipped"
    echo "========================================"

    # Merge coverage reports
    merge_lcov_files "${COVERAGE_SUITES[@]}"

    # List per-suite reports
    echo ""
    echo "[coverage] Per-suite reports:"
    for suite_name in "${COVERAGE_SUITES[@]}"; do
        safe_name="$(suite_to_safe_name "$suite_name")"
        lcov="tests/reports/coverage/${safe_name}.lcov"
        if [[ -f "$lcov" ]]; then
            echo "  - $suite_name: $lcov"
        fi
    done

    # Exit with failure if any tests failed
    if [[ $TOTAL_FAILED -gt 0 ]]; then
        exit 1
    fi
else
    # Run each suite in a separate Pandoc process (required for Pandoc >= 3.6
    # where long-lived Lua state causes SQLite locking issues across suites)
    echo "SpecCompiler E2E Test Runner"
    echo "============================================================"
    echo ""

    TOTAL_PASSED=0
    TOTAL_FAILED=0
    TOTAL_SKIPPED=0

    for suite in $(get_suites); do
        set +e
        output=$(run_suite "$suite" 2>&1)
        exit_code=$?
        set -e

        echo "$output"

        if [[ "$output" =~ Results:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed,\ ([0-9]+)\ skipped ]]; then
            TOTAL_PASSED=$((TOTAL_PASSED + ${BASH_REMATCH[1]}))
            TOTAL_FAILED=$((TOTAL_FAILED + ${BASH_REMATCH[2]}))
            TOTAL_SKIPPED=$((TOTAL_SKIPPED + ${BASH_REMATCH[3]}))
        fi

        echo ""
    done

    echo "============================================================"
    echo "Results: $TOTAL_PASSED passed, $TOTAL_FAILED failed, $TOTAL_SKIPPED skipped"
    echo "============================================================"

    if [[ $TOTAL_FAILED -gt 0 ]]; then
        exit 1
    fi
fi
