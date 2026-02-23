#!/bin/bash
# SpecCompiler - One-line remote installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/specir/SpecCompiler/main/scripts/remote_install.sh | bash
#
# What it does:
#   1. Downloads the specc wrapper to ~/.local/bin/specc
#   2. Writes a config pointing to the GHCR image
#   3. The Docker image is pulled lazily on first `specc build`

set -e

GITHUB_RAW="https://raw.githubusercontent.com/specir/SpecCompiler/main"
GHCR_REPOSITORY="specir/speccompiler"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler"

echo "=== SpecCompiler Installer ==="

# Check Docker is available
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed."
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

# Download the wrapper
echo "[1/3] Downloading wrapper..."
mkdir -p "$BIN_DIR"
curl -fsSL "$GITHUB_RAW/scripts/specc.sh" -o "$BIN_DIR/specc"
chmod +x "$BIN_DIR/specc"

# Write config pointing to GHCR
echo "[2/3] Writing config..."
mkdir -p "$CONFIG_DIR"
echo "SPECCOMPILER_REPOSITORY=\"${GHCR_REPOSITORY}\"" > "$CONFIG_DIR/env"

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
echo "The Docker image will be pulled automatically on first use."
echo ""
echo "Run: specc build [project.yaml]"
