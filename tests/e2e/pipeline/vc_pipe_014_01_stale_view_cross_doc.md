# spec: Pipeline Contract Validation @SPEC-PIPELINE-CONTRACTS-003

## section: Incremental Cross-Document View Freshness Contract @VC-PIPE-014

This test validates that an emitted output containing a view over other
documents' data (e.g., a traceability matrix) is regenerated when those other
documents change, even if the view's own document is cache-clean. The emit
skip decision must be based on the actual assembled document content, not on
a per-spec approximation of its dependencies.
