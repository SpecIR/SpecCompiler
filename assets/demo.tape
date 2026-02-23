# specc README demo
#
# Regenerate:  ./assets/demo.sh
# Record only: ./assets/demo.sh --record-only
# Render only: ./assets/demo.sh --render-only
#
# The demo uses tmux send-keys to drive real vim editing inside
# an asciinema recording.  All specc output is real.
#
# Two acts:
#   1. srs.md has invalid status:Pending on HLR → invalid_cast + traceability_hlr_to_vc (no VERIFIES relation)
#   2. Fix status:Draft + add svc.md with VC (VERIFIES @0420) → success (docx emitted)
#
# Requirements: asciinema, agg, tmux, vim, specc
#
# Render settings:
#   agg --theme dracula --font-size 14 --idle-time-limit 2.5 --last-frame-duration 4
