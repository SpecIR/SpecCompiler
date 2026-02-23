#!/bin/bash
# SpecCompiler Core - Docker Installer
# Builds Docker image and sets up wrapper script.

set -e

if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash, not sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="speccompiler-core"
IMAGE_TAG="latest"
BASE_IMAGE="speccompiler-core-base:latest"
TOOLCHAIN_IMAGE="speccompiler-toolchain:local"

# Parse arguments
FORCE=false
CODE_ONLY=false
NO_CACHE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --force) FORCE=true; shift ;;
    --code-only) CODE_ONLY=true; shift ;;
    --no-cache) NO_CACHE="--no-cache"; shift ;;
    --help|-h)
        echo "Usage: bash $0 [--force] [--code-only] [--no-cache]"
        echo ""
        echo "Options:"
        echo "  --force       Full rebuild including Pandoc/GHC toolchain compilation"
        echo "  --code-only   Update only src/ and models/ (requires existing image)"
        echo "  --no-cache    Pass --no-cache to docker build"
        exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [ "$FORCE" = true ] && [ "$CODE_ONLY" = true ]; then
    echo "Error: --force and --code-only are mutually exclusive"
    exit 1
fi

echo "=== SpecCompiler Core Docker Installer ==="

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

# Build the Docker image
echo "[1/3] Building Docker image..."
if [ "$CODE_ONLY" = true ]; then
    # Fast path: overlay src/ and models/ onto the stable runtime-base image.
    # Always builds from runtime-base (fixed layer count), never from itself,
    # preventing Docker "max depth exceeded" errors from layer accumulation.
    if ! docker image inspect "${BASE_IMAGE}" &> /dev/null; then
        echo "  Error: --code-only requires the base image ${BASE_IMAGE}"
        echo "  Run without --code-only first to build the base image"
        exit 1
    fi
    echo "  Code-only update: rebuilding src/ and models/ layers..."
    docker build $NO_CACHE \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
        --target codeonly \
        "$REPO_DIR"
    echo "  Code-only update complete"
    # Clean up dangling images left by the replaced tag
    docker image prune -f --filter "label!=keep" > /dev/null 2>&1 || true
elif [ "$FORCE" = false ] && docker image inspect "${IMAGE_NAME}:${IMAGE_TAG}" &> /dev/null; then
    echo "  Image exists, use --force to rebuild or --code-only to update Lua code"
else
    # Build toolchain locally if not present (or if --force).
    # This compiles Pandoc/GHC/Lua/Deno and takes a while on first run.
    if [ "$FORCE" = true ] || ! docker image inspect "${TOOLCHAIN_IMAGE}" &> /dev/null; then
        echo "  Building toolchain (first build compiles Pandoc/GHC — grab a coffee)..."
        docker build $NO_CACHE \
            -t "${TOOLCHAIN_IMAGE}" \
            --target toolchain \
            "$REPO_DIR"
        echo "  Toolchain built"
    else
        echo "  Toolchain image exists, skipping (use --force to rebuild)"
    fi
    # Build runtime-base (no application code) — stable base for --code-only
    echo "  Building runtime-base..."
    docker build $NO_CACHE \
        -t "${BASE_IMAGE}" \
        --build-arg "TOOLCHAIN_IMAGE=${TOOLCHAIN_IMAGE}" \
        --target runtime-base \
        "$REPO_DIR"
    # Build final runtime image (with src/ and models/)
    docker build $NO_CACHE \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        --build-arg "TOOLCHAIN_IMAGE=${TOOLCHAIN_IMAGE}" \
        --target runtime \
        "$REPO_DIR"
    echo "  Image built"
    # Clean up dangling images left by replaced tags
    docker image prune -f --filter "label!=keep" > /dev/null 2>&1 || true
fi

# Create Docker wrapper script
echo "[2/3] Setting up command-line tools..."
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/specc.sh" "$HOME/.local/bin/specc"
chmod +x "$HOME/.local/bin/specc"

# Write default image config
echo "[3/3] Writing default config..."
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler"
mkdir -p "$CONFIG_DIR"
echo "SPECCOMPILER_IMAGE=\"${IMAGE_NAME}:${IMAGE_TAG}\"" > "$CONFIG_DIR/env"

# Add to PATH if not already present
if [ -f "$HOME/.bashrc" ] && ! grep -q ".local/bin" "$HOME/.bashrc"; then
    echo "" >> "$HOME/.bashrc"
    echo "# Added by SpecCompiler installer" >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "  Added PATH to ~/.bashrc"
    echo ""
    echo "Run: source ~/.bashrc"
fi

echo ""
echo "=== Docker Installation Complete ==="
echo "Run: specc build project.yaml"
