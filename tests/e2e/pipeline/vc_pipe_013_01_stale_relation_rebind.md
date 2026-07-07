# spec: Pipeline Contract Validation @SPEC-PIPELINE-CONTRACTS-002

## section: Incremental Stale Relation Rebind Contract @VC-PIPE-013

This test validates that resolved cross-document relations do not survive an
incremental rebuild of the target document. Rebuilding a document deletes and
re-inserts its spec_objects rows, and SQLite may reuse the freed rowids, so a
cached document's resolved target_object_id can silently rebind to a different
object. Relations pointing into a rebuilt document must be re-resolved from
their target_text (or become unresolved when the target no longer exists).
