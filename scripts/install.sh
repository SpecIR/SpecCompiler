#!/bin/bash
# SpecCompiler - Installer (container mode)
#
# Installs the unified specc wrapper in image mode. Works both remotely and
# locally:
#   curl -fsSL https://raw.githubusercontent.com/specir/SpecCompiler/main/scripts/install.sh | bash
#   bash scripts/install.sh      # from a local clone
#
# Requires docker or podman. If a local image (speccompiler-core:latest)
# exists, it is used. Otherwise, the GHCR image is pulled lazily on first
# `specc build`.

set -e

GITHUB_RAW="https://raw.githubusercontent.com/specir/SpecCompiler/main"
GHCR_REPOSITORY="specir/speccompiler"
LOCAL_IMAGE="speccompiler-core:latest"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler"

# Detect whether we are running from a local repo clone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SPECC=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/specc" ]; then
    LOCAL_SPECC="$SCRIPT_DIR/specc"
fi

echo "=== SpecCompiler Installer ==="

# Pick a container engine: docker preferred, podman as fallback
if command -v docker &> /dev/null; then
    ENGINE=docker
elif command -v podman &> /dev/null; then
    ENGINE=podman
else
    echo "Error: no container engine found."
    echo "Install Docker (https://docs.docker.com/get-docker/) or Podman (https://podman.io),"
    echo "or use the native install: bash scripts/install-native.sh"
    exit 1
fi
echo "Using container engine: $ENGINE"

# Docker only: ensure current user can access the daemon without sudo
ADDED_DOCKER_GROUP=false
if [ "$ENGINE" = docker ] && ! docker info &> /dev/null; then
    if getent group docker &> /dev/null; then
        echo "Adding $USER to the docker group..."
        sudo usermod -aG docker "$USER"
        ADDED_DOCKER_GROUP=true
    else
        echo "Warning: Cannot connect to Docker daemon."
        echo "  Ensure Docker is running: sudo systemctl start docker"
    fi
fi

# Install the wrapper
echo "[1/3] Installing specc wrapper..."
mkdir -p "$BIN_DIR"
if [ -n "$LOCAL_SPECC" ]; then
    cp "$LOCAL_SPECC" "$BIN_DIR/specc"
else
    curl -fsSL "$GITHUB_RAW/scripts/specc" -o "$BIN_DIR/specc"
fi
chmod +x "$BIN_DIR/specc"

# Write config — prefer local image if it exists, otherwise GHCR.
# VAR="${VAR:-...}" lines keep exported environment variables in priority.
echo "[2/3] Writing config..."
mkdir -p "$CONFIG_DIR"
{
    printf 'SPECC_MODE="${SPECC_MODE:-image}"\n'
    printf 'SPECC_ENGINE="${SPECC_ENGINE:-%s}"\n' "$ENGINE"
    if "$ENGINE" image inspect "$LOCAL_IMAGE" &> /dev/null; then
        printf 'SPECCOMPILER_IMAGE="${SPECCOMPILER_IMAGE:-%s}"\n' "$LOCAL_IMAGE"
    else
        printf 'SPECCOMPILER_REPOSITORY="${SPECCOMPILER_REPOSITORY:-%s}"\n' "$GHCR_REPOSITORY"
    fi
} > "$CONFIG_DIR/env"
if "$ENGINE" image inspect "$LOCAL_IMAGE" &> /dev/null; then
    echo "  Using local image: $LOCAL_IMAGE"
else
    echo "  Using GHCR: ghcr.io/${GHCR_REPOSITORY}:latest"
    echo "  (image will be pulled on first use)"
fi

# Add to PATH if needed
echo "[3/3] Checking PATH..."
if [ -f "$HOME/.bashrc" ] && ! grep -q ".local/bin" "$HOME/.bashrc"; then
    echo "" >> "$HOME/.bashrc"
    echo "# Added by SpecCompiler installer" >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "  Added PATH to ~/.bashrc — run: source ~/.bashrc"
fi

echo ""
echo "=== Installation Complete ==="
echo "Run: specc build [project.yaml]"

# Activate docker group in current session (must be last — replaces shell)
if [ "$ADDED_DOCKER_GROUP" = true ]; then
    echo ""
    echo "Activating docker group..."
    exec newgrp docker
fi
