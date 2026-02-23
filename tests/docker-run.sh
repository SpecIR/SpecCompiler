#!/bin/bash
# SpecCompiler E2E Test Runner (Docker)
# Same interface as run.sh but executes inside Docker container
#
# Usage: ./docker-run.sh [suite] [test] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Docker image (should be pre-built with lua5.4, pandoc, etc.)
DOCKER_IMAGE="${SPECCOMPILER_DOCKER_IMAGE:-speccompiler-core:latest}"

# Resolve common fallback names
if ! docker image inspect "$DOCKER_IMAGE" > /dev/null 2>&1; then
    for fallback in "speccompiler-core-speccompiler-dev:latest" "speccompiler-core_speccompiler-dev:latest" "speccompiler/core:latest"; do
        if docker image inspect "$fallback" > /dev/null 2>&1; then
            DOCKER_IMAGE="$fallback"
            break
        fi
    done
fi

if ! docker image inspect "$DOCKER_IMAGE" > /dev/null 2>&1; then
    echo "Error: Docker image not found: $DOCKER_IMAGE"
    echo "Build it first with: bash scripts/install.sh --force"
    exit 1
fi

# Check if running interactively
if [ -t 0 ]; then
    DOCKER_OPTS="-it"
else
    DOCKER_OPTS=""
fi

# Run tests in Docker
docker run --rm $DOCKER_OPTS \
    --user "$(id -u):$(id -g)" \
    -v "$PROJECT_ROOT:/workspace" \
    -w /workspace \
    -e SPECCOMPILER_HOME=/workspace \
    "$DOCKER_IMAGE" \
    /workspace/tests/run.sh "$@"
