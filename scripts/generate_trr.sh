#!/bin/bash
set -e

# TRR Generator: Run e2e tests and generate Test Results Report markdown
# Usage: ./scripts/generate_trr.sh
#
# Delegates test execution to docker-run.sh (or run.sh if native),
# then generates TR markdown objects from JUnit XML.
# Output: docs/engineering_docs/test_results/tr.md (included by docs/engineering_docs/trr.md)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== TRR Generation Pipeline ==="
echo ""

# Detect environment: native (has pandoc + vendor libs) or Docker
use_native=false
LOCAL_PANDOC="$PROJECT_DIR/dist/bin/pandoc"
if [ -x "$LOCAL_PANDOC" ]; then
    PANDOC_CMD="$LOCAL_PANDOC"
    use_native=true
elif command -v pandoc > /dev/null 2>&1 && [ -f "$PROJECT_DIR/vendor/dkjson.lua" ]; then
    PANDOC_CMD="pandoc"
    use_native=true
fi

# Step 1: Run e2e tests with JUnit output
echo "[1/2] Running e2e tests with JUnit reporting..."
if $use_native; then
    "$PROJECT_DIR/tests/run.sh" --junit || true
else
    "$PROJECT_DIR/tests/docker-run.sh" --junit || true
fi

echo ""

# Step 2: Generate TRR markdown from JUnit XML
echo "[2/2] Generating TRR markdown..."
mkdir -p "$PROJECT_DIR/docs/engineering_docs/test_results"

JUNIT_PATH="$PROJECT_DIR/tests/reports/junit.xml"
OUTPUT_PATH="$PROJECT_DIR/docs/engineering_docs/test_results/tr.md"

if [ ! -f "$JUNIT_PATH" ]; then
    echo "ERROR: JUnit report not found at $JUNIT_PATH"
    echo "Tests may have failed to produce a report."
    exit 1
fi

if $use_native; then
    "$PANDOC_CMD" --lua-filter "$PROJECT_DIR/tests/helpers/trr_generator.lua" \
        --metadata junit_path="$JUNIT_PATH" \
        --metadata output_path="$OUTPUT_PATH" \
        < /dev/null
else
    # Resolve Docker image (same logic as docker-run.sh)
    DOCKER_IMAGE="${SPECCOMPILER_DOCKER_IMAGE:-speccompiler-core:latest}"
    for fallback in "speccompiler-core:dev" "speccompiler-core-speccompiler-dev:latest" "speccompiler-core_speccompiler-dev:latest"; do
        if docker image inspect "$fallback" > /dev/null 2>&1; then
            DOCKER_IMAGE="$fallback"
            break
        fi
    done
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$PROJECT_DIR:/workspace" -w /workspace \
        -e SPECCOMPILER_HOME=/workspace \
        "$DOCKER_IMAGE" \
        pandoc --lua-filter tests/helpers/trr_generator.lua \
            --metadata junit_path=tests/reports/junit.xml \
            --metadata output_path=docs/engineering_docs/test_results/tr.md \
            < /dev/null
fi

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_PATH"
echo "Run 'specc build' or docker equivalent to rebuild with test results."
