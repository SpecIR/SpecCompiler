## Pipeline Requirements

### SF: Pipeline Execution @SF-001

Five-phase document processing lifecycle with [TERM-16](@) orchestration and [TERM-25](@) ordering.

> description: Groups requirements for the core [TERM-15](@) that drives document processing
> through [TERM-19](@), [TERM-20](@), [TERM-22](@), [TERM-21](@), [TERM-23](@) phases with declarative handler dependencies.

> rationale: A structured processing pipeline enables separation of concerns, validation
> gates, and deterministic handler ordering.

### HLR: Five-Phase Lifecycle @HLR-PIPE-001

The pipeline shall execute handlers in a five-phase lifecycle: INITIALIZE, ANALYZE, TRANSFORM, VERIFY, EMIT.

> description: Each phase serves a distinct purpose in document processing:
>
> 1. **INITIALIZE**: Parse document AST and populate database with specifications, spec_objects, floats, relations, views, and attributes
> 2. **ANALYZE**: Resolve relations between objects (link target resolution, type inference)
> 3. **TRANSFORM**: Pre-compute views, render external content (PlantUML, charts), prepare for output
> 4. **VERIFY**: Run proof views to validate data integrity, type constraints, cardinality rules
> 5. **EMIT**: Assemble final documents and write to output formats (docx, html5, markdown, json)

> rationale: Separation of concerns enables validation between phases, allows early abort on errors, and supports format-agnostic processing until the final output stage.

> status: Approved

> belongs_to: [SF-001](@)

### HLR: Handler Registration and Prerequisites @HLR-PIPE-002

The pipeline shall support handler registration with declarative [TERM-24](@) for dependency ordering.

> description: Handlers register via `register_handler(handler)` with required fields:
>
> - `name`: Unique string identifier for the handler
> - `prerequisites`: Array of handler names that must execute before this handler
>
> Handlers declare participation in phases via hook methods (`on_initialize`, `on_analyze`, `on_verify`, `on_transform`, `on_emit`). Duplicate handler names cause registration error.

> rationale: Declarative prerequisites decouple handler ordering from registration order, enabling modular handler development and preventing implicit ordering dependencies.

> status: Approved

> belongs_to: [SF-001](@)

### HLR: Topological Ordering via Kahn's Algorithm @HLR-PIPE-003

The pipeline shall order handlers within each phase using topological sort with Kahn's algorithm.

> description: For each phase, the pipeline:
>
> 1. Identifies handlers participating in the phase (those with `on_{phase}` hooks)
> 2. Builds dependency graph from prerequisites (only for participating handlers)
> 3. Executes Kahn's algorithm to produce execution order
> 4. Sorts alphabetically at each level for deterministic output
> 5. Detects and reports circular dependencies with error listing remaining nodes

> rationale: Kahn's algorithm provides O(V+E) complexity, clear cycle detection, and deterministic ordering through alphabetic tie-breaking.

> status: Approved

> belongs_to: [SF-001](@)

### HLR: Phase Abort on VERIFY Errors @HLR-PIPE-004

The pipeline shall abort execution after VERIFY phase if any errors are recorded.

> description: After running VERIFY phase, the pipeline checks `diagnostics:has_errors()`. If true, execution halts before EMIT phase, with TRANSFORM already completed. Error message is logged with error count. This prevents generating invalid output from documents with specification violations.

> rationale: Early abort on verification failures saves computation and prevents distribution of invalid specification documents. Errors in VERIFY indicate data integrity issues that would produce incorrect outputs.

> status: Approved

> belongs_to: [SF-001](@)

### HLR: Batch Dispatch for All Phases @HLR-PIPE-005

The pipeline shall use a single batch dispatch model for all phases where handlers receive all contexts at once.

> description: All handlers implement `on_{phase}(data, contexts, diagnostics)` hooks that receive the full contexts array. The pipeline orchestrator calls each handler's hook once per phase via `run_phase()`, passing all document contexts. Handlers are responsible for iterating over contexts internally.
>
> This enables cross-document optimizations, transaction batching, and parallel processing within any phase.

> rationale: A uniform dispatch model simplifies the pipeline engine, eliminates the dual-path batch/per-doc dispatch, and allows handlers in any phase to optimize across all documents (e.g., wrapping DB operations in a single transaction, parallel output generation in EMIT).

> status: Approved

> belongs_to: [SF-001](@)

### HLR: Context Creation and Propagation @HLR-PIPE-006

The pipeline shall create and propagate context objects containing document metadata and configuration through all phases.

> description: The `execute(docs)` method creates context objects for each input document with:
>
> - `doc`: Pandoc document AST (via DocumentWalker)
> - `spec_id`: Specification identifier derived from filename
> - `config`: Preset configuration (styles, captions, validation)
> - `build_dir`: Output directory path
> - `output_format`: Target format (docx, html5, etc.)
> - `template`: Template name for model loading
> - `reference_doc`: Path to reference.docx for styling
> - `docx`, `html5`: Format-specific configuration
> - `outputs`: Array of {format, path} for multi-format output
> - `bibliography`, `csl`: Citation configuration
> - `project_root`: Root directory for resolving relative paths
>
> Context flows through all phases, enriched by handlers (e.g., verification results in VERIFY phase).

> rationale: Unified context object provides handlers with consistent access to document metadata and build configuration without global state, enabling testable and isolated handler implementations.

> status: Approved

> belongs_to: [SF-001](@)
