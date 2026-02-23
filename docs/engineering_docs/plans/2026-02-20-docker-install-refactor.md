# docker_install.sh Refactor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract the embedded wrapper script and inline Dockerfile from `docker_install.sh` into their own dedicated files so each file has a single responsibility and can be read, linted, and tested independently. Also add a one-line remote installer for users who don't need to clone the repo.

**Architecture:** Three files replace what was one. `scripts/speccompiler.sh` becomes the standalone wrapper that gets installed to `~/.local/bin/speccompiler`. `Dockerfile.codeonly` holds the fast code-update build. `docker_install.sh` becomes pure orchestration. A new `scripts/install.sh` (one-liner entrypoint) fetches just the wrapper from GitHub and writes a GHCR-pointing config — no repo clone needed. The wrapper's existing `ensure_image()` lazy-pulls the Docker image on first use.

**Tech Stack:** Bash, Docker

---

### Task 1: Extract wrapper to `scripts/speccompiler.sh`

**Files:**
- Create: `scripts/speccompiler.sh`
- Modify: `scripts/docker_install.sh` (lines 81–158, the `cat > ... << 'EOF'` block)

**Step 1: Create `scripts/speccompiler.sh`**

Copy the heredoc body verbatim (everything between `<< 'EOF'` and the closing `EOF` on line 158) into a new file. The file must be self-contained and executable:

```bash
#!/bin/bash
# SpecCompiler - Docker wrapper for speccompiler-core
# Installed to ~/.local/bin/speccompiler by scripts/docker_install.sh
set -e

SPECCOMPILER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/speccompiler/env"
[ -f "$SPECCOMPILER_CONFIG" ] && . "$SPECCOMPILER_CONFIG"

if [ -z "${SPECCOMPILER_IMAGE:-}" ] && [ -n "${SPECCOMPILER_REPOSITORY:-}" ]; then
    IMAGE="ghcr.io/${SPECCOMPILER_REPOSITORY}:latest"
else
    IMAGE="${SPECCOMPILER_IMAGE:-speccompiler-core:latest}"
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

usage() {
    echo -e "${CYAN}SpecCompiler${NC} - Requirements Engineering Language Compiler"
    echo ""
    echo "Usage: speccompiler build [project.yaml]"
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
```

**Step 2: Make it executable**

```bash
chmod +x scripts/speccompiler.sh
```

**Step 3: Verify it is valid bash**

```bash
bash -n scripts/speccompiler.sh
```
Expected: no output, exit code 0.

**Step 4: Replace the heredoc in `docker_install.sh`**

Replace the entire block (lines 81–159):
```bash
cat > "$HOME/.local/bin/speccompiler" << 'EOF'
...
EOF
chmod +x "$HOME/.local/bin/speccompiler"
```

With:
```bash
cp "$SCRIPT_DIR/speccompiler.sh" "$HOME/.local/bin/speccompiler"
chmod +x "$HOME/.local/bin/speccompiler"
```

**Step 5: Verify the installer is still valid bash**

```bash
bash -n scripts/docker_install.sh
```
Expected: no output, exit code 0.

**Step 6: Commit**

```bash
git add scripts/speccompiler.sh scripts/docker_install.sh
git commit -m "refactor: extract wrapper script to scripts/speccompiler.sh"
```

---

### Task 2: Extract inline Dockerfile to `Dockerfile.codeonly`

**Files:**
- Create: `Dockerfile.codeonly`
- Modify: `scripts/docker_install.sh` (lines 61–67, the `docker build -f - ... <<'CODEONLY_DOCKERFILE'` block)

**Step 1: Create `Dockerfile.codeonly`**

```dockerfile
# Fast code-only update — overlays src/ and models/ onto the existing image.
# Used by: scripts/docker_install.sh --code-only
# Requires the base speccompiler-core:latest image to already exist locally.
ARG BASE_IMAGE=speccompiler-core:latest
FROM ${BASE_IMAGE}
COPY src/    /opt/speccompiler/src/
COPY models/ /opt/speccompiler/models/
```

**Step 2: Replace the inline build block in `docker_install.sh`**

Replace:
```bash
    docker build $NO_CACHE \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f - "$REPO_DIR" <<'CODEONLY_DOCKERFILE'
FROM speccompiler-core:latest
COPY src/    /opt/speccompiler/src/
COPY models/ /opt/speccompiler/models/
CODEONLY_DOCKERFILE
```

With:
```bash
    docker build $NO_CACHE \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        --build-arg "BASE_IMAGE=${IMAGE_NAME}:${IMAGE_TAG}" \
        -f "$REPO_DIR/Dockerfile.codeonly" \
        "$REPO_DIR"
```

**Step 3: Verify `docker_install.sh` is still valid bash**

```bash
bash -n scripts/docker_install.sh
```
Expected: no output, exit code 0.

**Step 4: Commit**

```bash
git add Dockerfile.codeonly scripts/docker_install.sh
git commit -m "refactor: extract --code-only inline Dockerfile to Dockerfile.codeonly"
```

---

### Task 3: Add one-line remote installer `scripts/install.sh`

**Files:**
- Create: `scripts/install.sh`

**Step 1: Create `scripts/install.sh`**

This script is designed to be piped directly from `curl`. It must work without the repo being cloned — it fetches the wrapper from GitHub raw content, writes a GHCR config, and optionally patches PATH. The image is **not** pulled here; the wrapper's `ensure_image()` handles that lazily on first use.

```bash
#!/bin/bash
# SpecCompiler - One-line remote installer
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/<repo>/main/scripts/install.sh | bash
#
# What it does:
#   1. Downloads the speccompiler wrapper to ~/.local/bin/speccompiler
#   2. Writes a config pointing to the GHCR image
#   3. Symlinks sdn and spc
#   4. The Docker image is pulled lazily on first `speccompiler build`

set -e

GITHUB_RAW="https://raw.githubusercontent.com/<org>/<repo>/main"
GHCR_REPOSITORY="<org>/<repo>"
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
curl -fsSL "$GITHUB_RAW/scripts/speccompiler.sh" -o "$BIN_DIR/speccompiler"
chmod +x "$BIN_DIR/speccompiler"
ln -sf "$BIN_DIR/speccompiler" "$BIN_DIR/sdn"
ln -sf "$BIN_DIR/speccompiler" "$BIN_DIR/spc"

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
echo "Run: speccompiler build [project.yaml]"
```

> **Note:** Replace `<org>/<repo>` with the real GitHub slug before shipping. Consider making it a variable or passing it at install time.

**Step 2: Make it executable**

```bash
chmod +x scripts/install.sh
```

**Step 3: Verify syntax**

```bash
bash -n scripts/install.sh
```
Expected: no output, exit code 0.

**Step 4: Commit**

```bash
git add scripts/install.sh
git commit -m "feat: add one-line remote installer scripts/install.sh"
```

---

### Task 4: Smoke-test all scripts

**Step 1: Dry-run the dev installer (help flag)**

```bash
bash scripts/docker_install.sh --help
```
Expected: usage text printed, no errors.

**Step 2: Verify wrapper syntax**

```bash
bash -n scripts/speccompiler.sh
```
Expected: exit code 0.

**Step 3: Check wrapper help output**

```bash
bash scripts/speccompiler.sh --help
```
Expected: SpecCompiler usage text, no errors.

**Step 4: Verify one-line installer syntax**

```bash
bash -n scripts/install.sh
```
Expected: exit code 0.
