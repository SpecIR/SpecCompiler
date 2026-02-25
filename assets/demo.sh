#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# specc README demo — director script
#
# Uses tmux send-keys to drive real vim editing inside an
# asciinema recording.  All specc output is real.
#
# Usage:
#   ./assets/demo.sh                    # record + render GIF
#   ./assets/demo.sh --record-only      # just produce .cast
#   ./assets/demo.sh --render-only      # .cast → .gif
# ─────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAST="$SCRIPT_DIR/demo.cast"
GIF="$SCRIPT_DIR/demo.gif"
DEMO_DIR="/tmp/specc-demo-rec"
SESSION="specc-demo"
COLS=120
ROWS=26

# ── helpers ────────────────────────────────────────────────
type_text() {
    local text="$1"
    local delay="${2:-0.04}"
    for (( i=0; i<${#text}; i++ )); do
        local ch="${text:$i:1}"
        tmux send-keys -t "$SESSION" -l "$ch"
        sleep "$delay"
    done
}

send_enter() { tmux send-keys -t "$SESSION" Enter; }
send_escape() { tmux send-keys -t "$SESSION" Escape; }
send_key() { tmux send-keys -t "$SESSION" "$1"; }

type_cmd() {
    type_text "$1" "${2:-0.04}"
    sleep 0.15
    send_enter
}

wait_for() {
    local pattern="$1"
    local timeout="${2:-15}"
    local elapsed=0
    while ! tmux capture-pane -t "$SESSION" -p | grep -qF "$pattern"; do
        sleep 0.3
        elapsed=$(( elapsed + 1 ))
        if (( elapsed > timeout * 3 )); then
            echo "WARN: timeout waiting for '$pattern'" >&2
            return 0
        fi
    done
    sleep 0.3
}

# ── setup demo files ──────────────────────────────────────
setup_files() {
    rm -rf "$DEMO_DIR"
    mkdir -p "$DEMO_DIR"

    cat > "$DEMO_DIR/project.yaml" << 'YAML'
project:
  code: DEMO
  name: Demo
template: sw_docs
logging:
  level: info
  format: console
  color: true
output_dir: build
doc_files:
  - srs.md
  - svc.md
YAML

    cat > "$DEMO_DIR/srs.md" << 'MD'
# SRS: Login Service

## HLR: Authenticate Users @0013

The system shall authenticate users via OAuth 2.0.

> status: Pending
MD

    # svc.md — VC without traceability (added in Act 2)
    cat > "$DEMO_DIR/svc.md" << 'MD'
# SVC: Login Verification

## VC: Verify Authentication

Verify the authentication flow works end to end.

> objective: Confirm OAuth 2.0 login succeeds

> verification_method: Test
MD
}

# ── record ────────────────────────────────────────────────
record() {
    setup_files

    tmux kill-session -t "$SESSION" 2>/dev/null || true

    tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS"
    sleep 0.5

    # Set up shell inside tmux
    tmux send-keys -t "$SESSION" "export PS1='$ '" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION" "cd $DEMO_DIR" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION" "clear" Enter
    sleep 0.3

    # Start asciinema inside tmux
    tmux send-keys -t "$SESSION" \
        "asciinema rec --cols $COLS --rows $ROWS --overwrite $CAST -c 'bash --norc'" Enter
    sleep 1
    tmux send-keys -t "$SESSION" "export PS1='$ '" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION" "cd $DEMO_DIR" Enter
    sleep 0.2
    tmux send-keys -t "$SESSION" "clear" Enter
    sleep 0.8

    # ═════════════════════════════════════════════════════
    #  Act 1 — Build fails (invalid status + missing trace)
    # ═════════════════════════════════════════════════════
    type_cmd "specc build project.yaml"
    wait_for "Pipeline aborted"
    sleep 3

    # ═════════════════════════════════════════════════════
    #  Act 2 — Fix status:Pending → Draft + add traceability, success
    # ═════════════════════════════════════════════════════

    # -- Fix status in srs.md: :%s/Pending/Draft/ --
    type_cmd "vim srs.md"
    sleep 2.5

    type_text ":%s/Pending/Draft/" 0.05
    send_enter
    sleep 0.5

    send_escape
    sleep 0.3
    type_text ":wq" 0.08
    send_enter
    sleep 0.6

    # -- Add traceability to svc.md --
    type_cmd "vim svc.md"
    sleep 1

    # G → last line, o → open line below (insert mode)
    send_key "G"
    sleep 0.2
    send_key "o"
    sleep 0.3

    # Enter for blank line, then type the traceability attribute
    send_enter
    sleep 0.2
    type_text "> traceability: [0013](@)" 0.04
    sleep 0.4

    send_escape
    sleep 0.3
    type_text ":wq" 0.08
    send_enter
    sleep 0.6

    # Final build — should succeed
    type_cmd "specc build project.yaml"
    wait_for "Generated docx"
    sleep 3

    tmux kill-session -t "$SESSION" 2>/dev/null || true
    echo "Recording saved to $CAST"
}

# ── render ────────────────────────────────────────────────
render() {
    if [ ! -f "$CAST" ]; then
        echo "Error: $CAST not found. Run with --record-only first." >&2
        exit 1
    fi
    agg \
        --theme dracula \
        --font-size 14 \
        --idle-time-limit 2.5 \
        --last-frame-duration 4 \
        "$CAST" "$GIF"
    echo "GIF saved to $GIF ($(du -h "$GIF" | cut -f1))"
}

# ── main ──────────────────────────────────────────────────
case "${1:-}" in
    --record-only) record ;;
    --render-only) render ;;
    *)             record && render ;;
esac
