## Audit & Integrity Requirements

### SF: Audit and Integrity @SF-006

Deterministic compilation, reproducible builds, and audit trail integrity.

> description: Encompasses content-addressed hashing for incremental build detection,
> structured [dic:newline-delimited-json](#) logging for audit trails, include dependency tracking for
> proper cache invalidation, and structured diagnostic reporting for error traceability.

> rationale: Certification environments require reproducible builds and auditable
> processing trails for traceability evidence.

#### HLR: Content-Addressed Hashing @HLR-AUDIT-001

The system shall compute SHA1 content hashes for all source documents and include files to enable change detection.

> description: The build engine computes SHA1 hashes for each document. Hashes are compared against cached values in the `source_files` table:
>
> 1. If the content hash matches the cached hash, the system checks include file hashes
> 2. If all hashes match, the document is skipped (cached [dic:intermediate-representation](#) state is reused)
> 3. If any hash differs, the document is rebuilt from source
> 4. After successful rebuild (no [dic:verify-phase](#) errors), hashes are updated in the `source_files` table
>
> This provides O(1) change detection without parsing unchanged documents.

> rationale: Content-addressed hashing provides reliable change detection independent of filesystem timestamps. Deferred hash updates prevent cache poisoning from partial or failed builds.

> status: Approved


#### HLR: Include Dependency Tracking @HLR-AUDIT-002

When a document contains include directives, the system shall track all included file dependencies in a build graph and detect circular includes.

> description: Before [dic:pipeline](#) execution, the include handler expands `.include` code blocks by:
>
> 1. Resolving include paths relative to the source file directory
> 2. Detecting circular includes via a processed-file set (raises error on cycle)
> 3. Recursively expanding nested includes up to a bounded maximum depth
> 4. Recording all include paths and their SHA1 hashes in the `build_graph` table (`root_path`, `node_path`, `node_sha1`)
>
> Subsequent builds use this graph to check if any included file has changed, triggering a rebuild of the root document when needed.

> rationale: Include dependency tracking ensures that changes to sub-files correctly invalidate parent documents. Cycle detection prevents infinite recursion in include hierarchies.

> status: Approved


#### HLR: Structured Diagnostic Reporting @HLR-AUDIT-003

The system shall collect and report processing errors and warnings with source location information throughout all pipeline phases.

> description: The diagnostics collector provides structured error/warning reporting:
>
> 1. **Collection**: [dic:handler](#)s report issues via `diagnostics:error(file, line, code, msg)` and `diagnostics:warn(file, line, code, msg)`
> 2. **Structured data**: Each diagnostic record contains file path, line number, diagnostic code, and human-readable message
> 3. **Severity control**: The `has_errors()` method enables the [dic:pipeline](#) to determine abort conditions after the [dic:verify-phase](#) phase
> 4. **Output integration**: Diagnostics are emitted through the structured logger with file and line context
>
> Diagnostic codes follow domain prefixes (e.g., SD-102 for invalid enum, SD-201 for missing required attribute, SD-301 for dangling reference).

> rationale: Structured diagnostics with source locations enable IDE integration, CI/CD reporting, and user-friendly error resolution. Machine-parseable diagnostic codes enable automated error classification.

> status: Approved


#### HLR: Structured Logging @HLR-AUDIT-004

The system shall provide [dic:newline-delimited-json](#) structured logging with TTY-aware output formatting.

> description: The logging subsystem supports two output modes selected automatically or via configuration:
>
> 1. **NDJSON mode** (non-TTY): Outputs one JSON object per line with fields: `level`, `message`, `timestamp`, and optional context. Suitable for CI/CD log aggregation and `jq` filtering
> 2. **Console mode** (TTY): Outputs human-readable formatted messages with ANSI color coding (respects `NO_COLOR` environment variable). Includes timestamp and level indicator
>
> Log levels: DEBUG, INFO, WARN, ERROR. Configured via `config.logging.level` with environment override `SPECCOMPILER_LOG_LEVEL`.

> rationale: NDJSON enables machine-parseable audit trails for certification environments. TTY-aware formatting provides developer ergonomics during interactive use. The NO_COLOR standard ensures accessibility compliance.

> status: Approved


#### HLR: Build Reproducibility @HLR-AUDIT-005

Given identical source files, project configuration, and tool versions, the system shall produce identical outputs.

> description: Build reproducibility is ensured through:
>
> 1. **Deterministic parsing**: Content-addressable SHA1 identifiers ensure consistent object identity
> 2. **Deterministic ordering**: [dic:topological-sort](#) with alphabetic tie-breaking produces the same [dic:handler](#) execution order
> 3. **Deterministic numbering**: Float numbers assigned by `file_seq` ordering, which is stable across builds
> 4. **Deterministic output**: Pandoc invoked with the same arguments and reference documents produces identical output
>
> Cache invalidation is based solely on content hashes, not filesystem timestamps or system state.

> rationale: Reproducible builds are a fundamental certification requirement in aerospace and safety-critical domains. Content-addressed processing ensures that build artifacts can be independently verified.

> status: Approved

