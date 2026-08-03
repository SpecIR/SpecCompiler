# spec: Pipeline Contract Validation @SPEC-PIPELINE-CONTRACTS-003

## section: Incremental Allocation View Freshness Contract @VC-PIPE-014

This test validates that the allocation matrix view renders live from the
database on every build. A cached (unchanged) document containing
`allocation_matrix:` must still reflect edits made to other documents whose
objects feed the matrix — no stale precomputed rendering may be served.
