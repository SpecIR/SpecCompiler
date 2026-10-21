# spec: Pipeline Contract Validation @SPEC-PIPELINE-CONTRACTS-004

## section: Cross-Specification PID Auto-Generation Contract @VC-PIPE-010

This test validates that auto-generated PIDs are unique across all
specifications of a project, not just within one specification. Two documents
with objects of the same sequential type and no explicit `@PID` must not both
receive the same PID (e.g., `HLR-001`), auto-generated PIDs must probe past
explicit PIDs claimed in another document, and an incremental rebuild of one
document must not reintroduce a collision with a cached document.
