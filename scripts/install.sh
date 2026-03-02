#!/bin/bash
# SpecCompiler - Installer
#
# Installs the specc wrapper command. Works both remotely and locally:
#   curl -fsSL https://raw.githubusercontent.com/specir/SpecCompiler/main/scripts/install.sh | bash
#   bash scripts/install.sh      # from a local clone
#
# If a local Docker image (speccompiler-core:latest) exists, it is used.
# Otherwise, the GHCR image is pulled lazily on first `specc build`.

set -e

GITHUB_RAW="https://raw.githubusercontent.com/specir/SpecCompiler/main"
GHCR_REPOSITORY="specir/speccompiler"
LOCAL_IMAGE="speccompiler-core:latest"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler"

# Detect whether we are running from a local repo clone
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SPECC=""
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/specc.sh" ]; then
    LOCAL_SPECC="$SCRIPT_DIR/specc.sh"
fi

echo "=== SpecCompiler Installer ==="

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed."
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# Ensure current user can access Docker without sudo
ADDED_DOCKER_GROUP=false
if ! docker info &> /dev/null; then
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
    curl -fsSL "$GITHUB_RAW/scripts/specc.sh" -o "$BIN_DIR/specc"
fi
chmod +x "$BIN_DIR/specc"

# Write config — prefer local image if it exists, otherwise GHCR
echo "[2/3] Writing config..."
mkdir -p "$CONFIG_DIR"
if docker image inspect "$LOCAL_IMAGE" &> /dev/null 2>&1; then
    echo "SPECCOMPILER_IMAGE=\"${LOCAL_IMAGE}\"" > "$CONFIG_DIR/env"
    echo "  Using local image: $LOCAL_IMAGE"
else
    echo "SPECCOMPILER_REPOSITORY=\"${GHCR_REPOSITORY}\"" > "$CONFIG_DIR/env"
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
