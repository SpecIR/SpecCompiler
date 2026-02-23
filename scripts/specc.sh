#!/bin/bash
# SpecCompiler - Docker wrapper for speccompiler-core
# Installed to ~/.local/bin/specc by scripts/install.sh
set -e

# Source persistent config if it exists (written by installers).
SPECCOMPILER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler/env"
[ -f "$SPECCOMPILER_CONFIG" ] && . "$SPECCOMPILER_CONFIG"

if [ -z "${SPECCOMPILER_IMAGE:-}" ] && [ -n "${SPECCOMPILER_REPOSITORY:-}" ]; then
    IMAGE="ghcr.io/${SPECCOMPILER_REPOSITORY}:latest"
else
    IMAGE="${SPECCOMPILER_IMAGE:-speccompiler-core:latest}"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

usage() {
    echo -e "${CYAN}SpecCompiler${NC}"
    echo ""
    echo "Usage: specc build [project.yaml]"
    echo ""
    echo "  Build the project (default: project.yaml)"
    echo ""
    echo "Environment:"
    echo "  SPECCOMPILER_IMAGE        Full image reference (highest priority)"
    echo "  SPECCOMPILER_REPOSITORY   GitHub slug to resolve GHCR image (e.g. org/repo)"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker not found${NC}"
        echo "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    if ! docker info &> /dev/null; then
        echo -e "${RED}Error: Docker daemon is not running${NC}"
        exit 1
    fi
}

ensure_image() {
    if ! docker image inspect "$IMAGE" &> /dev/null; then
        echo -e "${CYAN}Docker image '$IMAGE' not found locally. Pulling...${NC}"
        if ! docker pull "$IMAGE"; then
            echo -e "${RED}Error: Failed to pull image '$IMAGE'${NC}"
            echo "If this is a local dev image, build it with:"
            echo "  docker build -t speccompiler-core:latest ."
            exit 1
        fi
    fi
}

cmd_build() {
    check_docker; ensure_image
    local project_file="${1:-project.yaml}"
    if [ ! -f "$project_file" ]; then
        echo -e "${RED}Error: $project_file not found${NC}"; exit 1
    fi
    echo -e "${CYAN}Building project...${NC}"
    docker run --rm \
        -u "$(id -u):$(id -g)" \
        -v "$(pwd):/workspace" \
        -w /workspace \
        -e "SPECCOMPILER_HOME=/opt/speccompiler" \
        -e "SPECCOMPILER_DIST=/opt/speccompiler" \
        -e "SPECCOMPILER_LOG_LEVEL=${SPECCOMPILER_LOG_LEVEL:-INFO}" \
        "$IMAGE" /opt/speccompiler/bin/speccompiler-core "$project_file"
    echo -e "${GREEN}Build complete.${NC}"
}

case "${1:-}" in
    build)  shift; cmd_build "$@" ;;
    -h|--help|help|"") usage ;;
    *)  echo -e "${RED}Unknown command: $1${NC}"; usage; exit 1 ;;
esac
