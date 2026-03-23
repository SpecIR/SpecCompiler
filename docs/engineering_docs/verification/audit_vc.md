## Audit & Integrity Verification Cases

### VC: Content-Addressed Hashing @VC-AUDIT-001

Verify that SHA1 content hashing correctly detects document changes and skips unchanged documents.

> objective: Confirm that the build engine computes SHA1 hashes, caches them in `source_files`, and correctly distinguishes dirty from clean documents

> verification_method: Test

> approach:
> - Build a project with two documents
> - Rebuild without changes; verify both documents are skipped (cache hit)
> - Modify one document; rebuild and verify only the modified document is reprocessed
> - Verify `source_files` table contains updated hash after successful build

> pass_criteria:
> - Unchanged documents produce cache hits (no re-parsing)
> - Modified documents produce cache misses (full reprocessing)
> - Hash values in `source_files` table match actual file content SHA1
> - Hashes are not updated when VERIFY phase produces errors

> traceability: [HLR-AUDIT-001](@), [LLR-084](@), [LLR-085](@)

### VC: Include Dependency Tracking @VC-AUDIT-002

Verify that include file changes trigger parent document rebuilds and that circular includes are detected.

> objective: Confirm that the build graph tracks include dependencies and detects cycles

> verification_method: Test

> approach:
> - Build a project where document A includes file B
> - Modify file B without changing document A; rebuild
> - Verify document A is rebuilt due to include dependency
> - Create a circular include (A includes B, B includes A)
> - Verify circular include produces an error diagnostic

> pass_criteria:
> - `build_graph` table contains entries for root document and all included files
> - Modifying an included file triggers rebuild of the root document
> - Circular includes produce a diagnostic error before pipeline execution
> - Include paths are resolved relative to the including file's directory

> traceability: [HLR-AUDIT-002](@), [LLR-086](@), [LLR-087](@)

### VC: Structured Diagnostic Reporting @VC-AUDIT-003

Verify that the diagnostics system collects errors and warnings with source location information.

> objective: Confirm that diagnostic collection, severity control, and abort behavior work correctly

> verification_method: Test

> approach:
> - Process a document with known validation errors (missing required attribute, invalid enum)
> - Verify each error includes file path, line number, diagnostic code, and message
> - Verify `has_errors()` returns true after error collection
> - Verify pipeline aborts before EMIT when errors exist
> - Process a document with warnings only; verify pipeline continues to EMIT

> pass_criteria:
> - Each diagnostic contains non-empty file, line, code, and message fields
> - `has_errors()` returns true when errors exist, false for warnings only
> - Pipeline does not execute EMIT phase when `has_errors()` is true
> - Warnings are reported but do not prevent output generation

> traceability: [HLR-AUDIT-003](@), [LLR-088](@), [LLR-089](@)

### VC: Structured Logging @VC-AUDIT-004

Verify that the logger produces correctly formatted output in both NDJSON and console modes.

> objective: Confirm TTY-aware mode selection, NDJSON format compliance, and NO_COLOR support

> verification_method: Inspection

> approach:
> - Inspect logger output in non-TTY mode (piped to file)
> - Verify each line is valid JSON with required fields (level, message, timestamp)
> - Inspect logger output in TTY mode
> - Verify ANSI color codes are present in normal mode and absent when NO_COLOR is set
> - Verify log level filtering respects configured level

> pass_criteria:
> - Non-TTY output consists of valid JSON objects, one per line
> - Each JSON object contains at minimum: level, message, timestamp
> - TTY output includes ANSI color codes for level indicators
> - Setting NO_COLOR environment variable suppresses ANSI codes
> - Messages below configured log level are not emitted

> traceability: [HLR-AUDIT-004](@), [LLR-090](@), [LLR-091](@)

### VC: Build Reproducibility @VC-AUDIT-005

Verify that identical inputs produce identical outputs across separate build invocations.

> objective: Confirm deterministic compilation from source to output

> verification_method: Test

> approach:
> - Build a project with multiple documents, floats, and cross-references
> - Record SHA1 hashes of all output files (DOCX, HTML5)
> - Delete build cache and rebuild from scratch
> - Compare output file hashes against the first build

> pass_criteria:
> - Output files from both builds have identical SHA1 hashes
> - Float numbering is identical across builds
> - Cross-reference link targets are identical across builds
> - Handler execution order is identical across builds (verified via debug logging)

> traceability: [HLR-AUDIT-005](@), [LLR-092](@), [LLR-093](@)
