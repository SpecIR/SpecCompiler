## Pipeline Design

### FD: Pipeline Execution Orchestration @FD-001

> traceability: [SF-001](@)

**Allocation:** Realized by [CSC-001](@) (Core Runtime) through [CSU-005](@) (Build Engine) and [CSU-006](@) (Pipeline Orchestrator), with handlers registered via [CSC-003](@) (Pipeline Handlers). Phase-specific handlers are organized in [CSC-008](@) (Analyze Handlers), [CSC-010](@) (Initialize Handlers), and [CSC-012](@) (Transform Handlers), with shared utilities in [CSC-011](@) (Shared Pipeline Utilities).

The [dic:pipeline](#) execution orchestration function manages the five-phase document processing
lifecycle from initial Pandoc hook entry through final output generation. It encompasses
[dic:handler](#) registration, dependency-based execution ordering, context propagation, and
phase abort logic.

**Entry Point**: The Pandoc filter ([CSU-005](@)) hooks into the Pandoc Meta callback, extracts
project metadata via [CSU-009](@), and invokes the build engine. The engine creates the
database, initializes the data manager, loads the model via [CSU-008](@), processes
document files (with [dic:build-cache](#) checks), and delegates to the pipeline orchestrator.

**Handler Registration**: During model loading, [CSU-008](@) registers each handler with the Pipeline Orchestrator [CSU-006](@), which enforces the registration contract by validating that every handler declares both a `name` and a `[dic:prerequisites](#)` field before accepting registration. The orchestrator rejects duplicate handler names — attempting to register a handler whose name already exists raises an immediate error. Accepted handlers are stored in a lookup table keyed by name for O(1) retrieval during phase execution. Each handler implements phase hooks using the naming convention `on_{phase}` (e.g., `on_initialize`, `on_analyze`, `on_transform`, `on_verify`, `on_emit`). All hooks receive the full contexts array: `on_{phase}(data, contexts, diagnostics)`.

**[dic:topological-sort](#)**: Before executing each phase, the Pipeline Orchestrator [CSU-006](@) applies Kahn's algorithm to produce a deterministic handler execution order. Only handlers that implement an `on_{phase}` hook for the current phase participate in the sort; handlers without a relevant hook are skipped entirely. The algorithm begins by building a dependency graph restricted to participants and initializing an in-degree count for each node. Nodes with zero in-degree — handlers whose prerequisites are already satisfied — seed a processing queue. At each step the algorithm dequeues the first node, appends it to the sorted output, and decrements the in-degree of all its dependents; any dependent whose in-degree reaches zero is enqueued. Alphabetical tie-breaking is applied at every dequeue step so that handlers at the same dependency depth are always emitted in the same order, guaranteeing deterministic output across runs. After the queue is exhausted, if the sorted list length is less than the participant count a dependency cycle exists and is reported as an error.

> For example, if INITIALIZE has three handlers — `specifications` (no prerequisites), `spec_objects` (prerequisite: `specifications`), and `spec_floats` (prerequisite: `specifications`) — the sort produces `[specifications, spec_floats, spec_objects]`, with `spec_floats` and `spec_objects` ordered alphabetically since both depend only on `specifications`.

**Phase Execution**: The pipeline executes five phases in order:

1. **[dic:initialize-phase](#)** — Parse Pandoc [dic:abstract-syntax-tree](#) into [dic:intermediate-representation](#) database tables (specifications,
   spec_objects, attributes, spec_floats, spec_views, spec_relations)
2. **[dic:analyze-phase](#)** — Resolve cross-references and infer relation types
3. **[dic:transform-phase](#)** — Render content, materialize views, execute external renderers
4. **[dic:verify-phase](#)** — Run proof views and collect diagnostics
5. **[dic:emit-phase](#)** — Assemble documents and generate output files

All phases use the same dispatch model: for each handler in sorted order, the Pipeline Orchestrator [CSU-006](@) calls the handler's `on_{phase}(data, contexts, diagnostics)` hook once with the full set of contexts. Handlers are responsible for iterating over contexts internally. Each handler invocation is bracketed by `uv.hrtime()` calls at nanosecond precision to record its duration, and the orchestrator also records the aggregate duration of each phase, providing two-level performance visibility (handler-level and phase-level).

**Phase Abort**: After VERIFY, the Pipeline Orchestrator [CSU-006](@) inspects the diagnostics collector for any error-level entries. If errors exist, the pipeline aborts before EMIT — only output generation is skipped, since TRANSFORM has already completed. This design allows proof views to validate transform results before committing to output.

**Context Propagation**: Each document file produces a context containing the parsed AST,
file path, specification ID, and walker state. Contexts are passed through all phases,
accumulating state. The diagnostics collector aggregates errors and warnings across all
handlers and contexts.

**Component Interaction**

The pipeline is realized through the core runtime and four handler packages that
correspond to pipeline phases.

[csc:core-runtime](#) (Core Runtime) provides the entry point and orchestration layer. [csu:pandoc-filter-entry-point](#)
(Pandoc Filter Entry Point) hooks into the Pandoc callback to launch the build. [csu:configuration-parser](#)
(Configuration Parser) reads `project.yaml` and resolves model, output, and logging settings.
[csu:data-loader](#) (Data Loader) loads external data files referenced by specifications. [csu:build-engine](#)
(Build Engine) coordinates the full build lifecycle — creating the database, loading the
model, processing document files with cache checks, and delegating to [csu:pipeline-orchestrator](#) (Pipeline
Orchestrator) for phase execution. The orchestrator drives topological sort, handler dispatch,
timing, and abort logic across all five phases.

[csc:pipeline-handlers](#) (Pipeline Handlers) registers cross-cutting handlers. [csu:include-expansion-filter](#) (Include
Expansion Filter) resolves `include` directives during INITIALIZE, expanding referenced
files into the document AST before entity parsing begins.

[csc:initialize-handlers](#) (Initialize Handlers) parses the Pandoc AST into SpecIR entities. [csu:specification-parser](#)
(Specification Parser) extracts document-level metadata, [csu:object-parser](#) (Object Parser) identifies
typed content blocks, [csu:attribute-parser](#) (Attribute Parser) extracts key-value attributes from object
paragraphs, [csu:float-parser](#) (Float Parser) detects embedded figures, tables, and listings,
[csu:relation-parser](#) (Relation Parser) captures cross-reference links, and [csu:view-parser](#) (View Parser)
identifies view directives.

[csc:analyze-handlers](#) (Analyze Handlers) resolves cross-references and infers types. [csu:relation-resolver](#)
(Relation Resolver) matches link targets to spec objects using selector-based resolution.
[csu:relation-type-inferrer](#) (Relation Type Inferrer) assigns relation type_refs based on source and target
object types. [csu:attribute-caster](#) (Attribute Caster) validates and casts attribute values against their
declared datatypes.

[csc:shared-pipeline-utilities](#) (Shared Pipeline Utilities) provides reusable base modules consumed by handlers
across phases. [csu:spec-object-base](#) (Spec Object Base) and [csu:specification-base](#) (Specification Base) provide
shared parsing logic for objects and specifications. [csu:float-base](#) (Float Base) provides
float detection and extraction. [csu:attribute-paragraph-utilities](#) (Attribute Paragraph Utilities) parses attribute
blocks from definition-list paragraphs. [csu:include-handler](#) (Include Handler) and [csu:include-utilities](#)
(Include Utilities) manage file inclusion and path resolution. [csu:render-utilities](#) (Render Utilities)
and [csu:math-render-utilities](#) (Math Render Utilities) provide AST-to-output conversion helpers. [csu:view-utilities](#)
(View Utilities) supports view parsing and materialization. [csu:source-position-compatibility](#) (Source Position
Compatibility) normalizes Pandoc source position data across API versions.

```puml:fd-001-pipeline{caption="Pipeline Execution Orchestration"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Pipeline\nOrchestrator" as P
participant "CSC-010 Initialize\nHandlers" as INIT
participant "CSC-008 Analyze\nHandlers" as ANLZ
participant "CSC-012 Transform\nHandlers" as XFRM
participant "CSC-009 Emit\nHandlers" as EMIT_H
participant "CSU Data Manager" as DB

E -> P: execute(walkers)

== INITIALIZE ==
P -> P: topological_sort("initialize")
P -> INIT: specifications.on_initialize()
INIT -> DB: INSERT specifications
P -> INIT: spec_objects.on_initialize()
INIT -> DB: INSERT spec_objects
P -> INIT: spec_floats.on_initialize()
INIT -> DB: INSERT spec_floats
P -> INIT: attributes.on_initialize()
INIT -> DB: INSERT spec_attribute_values
P -> INIT: spec_relations.on_initialize()
INIT -> DB: INSERT spec_relations
P -> INIT: spec_views.on_initialize()
INIT -> DB: INSERT spec_views

== ANALYZE ==
P -> P: topological_sort("analyze")
P -> ANLZ: pid_generator.on_analyze()
ANLZ -> DB: UPDATE spec_objects SET pid
P -> ANLZ: relation_analyzer.on_analyze()
ANLZ -> DB: UPDATE spec_relations\n(resolve targets, infer types)

== TRANSFORM ==
P -> P: topological_sort("transform")
P -> XFRM: view_materializer.on_transform()
XFRM -> DB: UPDATE spec_views.resolved_data
P -> XFRM: spec_floats.on_transform()
XFRM -> DB: UPDATE spec_floats.resolved_ast
P -> XFRM: external_render_handler.on_transform()
XFRM -> DB: UPDATE resolved_ast\n(subprocess results)
P -> XFRM: float_numbering.on_transform()
XFRM -> DB: UPDATE spec_floats SET number
P -> XFRM: specification_render_handler.on_transform()
XFRM -> DB: UPDATE specifications.header_ast
P -> XFRM: spec_object_render_handler.on_transform()
XFRM -> DB: UPDATE spec_objects.ast
P -> XFRM: relation_link_rewriter.on_transform()
XFRM -> DB: UPDATE spec_objects.ast\n(rewrite links)

== VERIFY ==
P -> P: topological_sort("verify")
P -> DB: SELECT * FROM proof views
DB --> P: violation rows

alt errors exist
    P --> E: abort (skip EMIT)
else no errors
    == EMIT ==
    P -> P: topological_sort("emit")
    P -> EMIT_H: reqif_xhtml.on_emit()
    EMIT_H -> DB: SELECT spec_objects, cache XHTML
    P -> EMIT_H: fts_indexer.on_emit()
    EMIT_H -> DB: INSERT INTO fts_objects,\nfts_attributes, fts_floats
    P -> EMIT_H: emitter.on_emit()
    EMIT_H -> DB: SELECT assembled content
    EMIT_H -> EMIT_H: parallel pandoc output
end

P --> E: diagnostics
@enduml
```

#### LLR: Handler Registration Requires Name @LLR-PIPE-002-01

Pipeline handler registration shall reject handlers that do not
provide a non-empty `name` field.

> verification_method: Test

> traceability: [HLR-PIPE-002](@)

#### LLR: Handler Registration Requires Prerequisites @LLR-PIPE-002-02

Pipeline handler registration shall reject handlers that do not
provide a `prerequisites` array.

> verification_method: Test

> traceability: [HLR-PIPE-002](@)

#### LLR: Duplicate Handler Names Are Rejected @LLR-PIPE-002-03

Pipeline handler registration shall reject duplicate handler
names within the same pipeline instance.

> verification_method: Test

> traceability: [HLR-PIPE-002](@)

#### LLR: Base Context Fields Are Propagated @LLR-PIPE-006-01

Pipeline execution shall propagate the base context fields
(`validation`, `build_dir`, `log`, `output_format`, `template`, `reference_doc`,
`docx`, `project_root`, `outputs`, `html5`, `bibliography`, `csl`) to handlers.

> verification_method: Test

> traceability: [HLR-PIPE-006](@)

#### LLR: Document Context Is Attached Per Document @LLR-PIPE-006-02

Pipeline execution shall attach `doc` and `spec_id` for each
processed document context passed to handlers.

> verification_method: Test

> traceability: [HLR-PIPE-006](@)

#### LLR: Project Context Exists Without Documents @LLR-PIPE-006-03

Pipeline execution shall create a fallback project context when
the document list is empty, with `doc=nil` and a derived `spec_id`.

> verification_method: Test

> traceability: [HLR-PIPE-006](@)

#### LLR: Phase Execution Order @LLR-020

Given registered [dic:handler](#)s, [csu:pipeline-orchestrator](#) shall execute phases in fixed order:
[dic:initialize-phase](#) → [dic:analyze-phase](#) → [dic:transform-phase](#) → [dic:verify-phase](#) → [dic:emit-phase](#).

> verification_method: Test

> traceability: [HLR-PIPE-001](@)

#### LLR: Phase Hook Filtering @LLR-021

Given the [dic:handler](#) set for a [dic:phase](#), [csu:pipeline-orchestrator](#) shall invoke only
those declaring an `on_{phase}` hook for that phase.

> verification_method: Test

> traceability: [HLR-PIPE-001](@)

#### LLR: No EMIT After Abort @LLR-022

When `diagnostics:has_errors()` returns true after [dic:verify-phase](#), [csu:pipeline-orchestrator](#)
shall not execute [dic:emit-phase](#) phase handlers.

> verification_method: Test

> traceability: [HLR-PIPE-001](@)

#### LLR: Topological Sort Phase Filtering @LLR-023

Given a [dic:phase](#) name and the [dic:handler](#) registry, [csu:pipeline-orchestrator](#) shall
build the [dic:topological-sort](#) dependency graph from only those handlers declaring an
`on_{phase}` hook, producing an ordered execution list.

> verification_method: Test

> traceability: [HLR-PIPE-003](@)

#### LLR: Alphabetic Tie-Breaking @LLR-024

When multiple [dic:handler](#)s have no dependency ordering between them,
[csu:pipeline-orchestrator](#) shall sort them alphabetically by `name`, producing deterministic
output.

> verification_method: Test

> traceability: [HLR-PIPE-003](@)

#### LLR: Circular Dependency Reporting @LLR-025

When a cyclic [dic:prerequisites](#) graph is detected, [csu:pipeline-orchestrator](#) shall report an
error listing the remaining unordered handler names.

> verification_method: Test

> traceability: [HLR-PIPE-003](@)

#### LLR: TRANSFORM Completes Before Abort Check @LLR-026

[csu:build-engine](#) shall complete all [dic:transform-phase](#) phase handlers before checking
`has_errors()` for abort, ensuring transforms are applied before validation
results are inspected.

> verification_method: Test

> traceability: [HLR-PIPE-004](@)

#### LLR: Abort Logs Error Count @LLR-027

When aborting execution before [dic:emit-phase](#), [csu:build-engine](#) shall log the error
count via [csu:logger](#).

> verification_method: Test

> traceability: [HLR-PIPE-004](@)

#### LLR: Full Contexts Array Dispatch @LLR-028

Given a document context array, [csu:pipeline-orchestrator](#) shall pass the full array to each
[dic:handler](#)'s `on_{phase}` hook in a single call.

> verification_method: Test

> traceability: [HLR-PIPE-005](@)

#### LLR: Handler Hook Signature @LLR-029

[csu:pipeline-orchestrator](#) shall invoke phase hooks with signature
`on_{phase}(data, contexts, diagnostics)` where `data` is a [csu:data-manager](#)
instance, `contexts` is the array, and `diagnostics` is a [csu:diagnostics-collector](#) instance.

> verification_method: Test

> traceability: [HLR-PIPE-005](@)

#### LLR: L1 Headers Register as Specifications @LLR-030

Given a Pandoc Header at level 1 in the [dic:abstract-syntax-tree](#), [csu:specification-parser](#) shall parse
the optional `TYPE:` prefix and `@`[dic:project-identifier](#) suffix and insert one
[dic:specification](#) record into the `specifications` table with `identifier` derived
from filename, `type_ref` validated against the [dic:type-registry](#), and `header_ast`
storing the serialized [dic:abstract-syntax-tree](#).

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: L2-H6 Headers Register as Spec Objects @LLR-031

Given a Pandoc Header at level 2–6, [csu:object-parser](#) shall insert one [dic:spec-object](#)
record with type resolved via explicit `TYPE:` prefix → [dic:type-alias](#) lookup →
default fallback.

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: Blockquotes Register as Attributes @LLR-032

Given Pandoc BlockQuote lines matching `> key: value`, [csu:attribute-parser](#) shall insert
[dic:attribute](#) records in `spec_attribute_values` linked to the enclosing
[dic:spec-object](#) via `owner_object_id`.

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: Code Blocks Register as Floats @LLR-033

Given a Pandoc CodeBlock with `syntax:label` class, [csu:float-parser](#) shall insert
one [dic:spec-float](#) record with `type_ref` resolved from [dic:type-alias](#), `label`,
and `raw_content`.

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: Links Register as Relations @LLR-034

Given a Pandoc Link with `(@)` or `(#)` target, [csu:relation-parser](#) shall insert one
[dic:spec-relation](#) record with `target_text` and [dic:relation-selector](#) preserved for
downstream resolution.

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: Content-Addressable Identifiers and Document Order @LLR-035

For any [dic:intermediate-representation](#) record, [csu:object-parser](#) and [csu:hash-utilities](#) shall compute
`identifier` as SHA1 hash of source context and assign `file_seq` preserving
document order.

> verification_method: Test

> traceability: [HLR-PIPE-007](@)

#### LLR: Include Path Resolution @LLR-036

Given `.include` CodeBlock paths, [csu:include-expansion-filter](#) shall resolve each path relative
to the including file's directory.

> verification_method: Test

> traceability: [HLR-PIPE-008](@)

#### LLR: Circular Include Detection @LLR-037

When recursive include traversal detects a cycle, [csu:include-expansion-filter](#) shall raise an
error with the include chain path before performing any expansion.

> verification_method: Test

> traceability: [HLR-PIPE-008](@)

#### LLR: Source Position Injection @LLR-038

After expanding included content, [csu:include-expansion-filter](#) shall inject `data-source-file`
and `data-pos` attributes into expanded blocks for diagnostic tracing.

> verification_method: Test

> traceability: [HLR-PIPE-008](@)

#### LLR: Non-Composite PID Format @LLR-039

Given a non-[dic:composite-object-type](#) [dic:spec-object](#) without explicit
`@`[dic:project-identifier](#), the pid_generator shall produce a [dic:project-identifier](#) using
`pid_prefix` + `pid_format` from the [dic:type](#) definition (e.g.,
`HLR-%03d` → `HLR-001`).

> verification_method: Test

> traceability: [HLR-PIPE-009](@)

#### LLR: Composite Hierarchical PID @LLR-040

Given a [dic:composite-object-type](#) [dic:spec-object](#) without explicit `@`[dic:project-identifier](#),
the pid_generator shall produce a hierarchical [dic:project-identifier](#) qualified by the
[dic:specification](#) PID (e.g., `SRS-sec1.2.3`).

> verification_method: Test

> traceability: [HLR-PIPE-009](@)

#### LLR: Explicit PID Preservation @LLR-041

Given a [dic:spec-object](#) with explicit `@`[dic:project-identifier](#) annotation, the
pid_generator shall preserve the PID unchanged.

> verification_method: Test

> traceability: [HLR-PIPE-009](@)

#### LLR: PID Collision Detection @LLR-042

After generating a [dic:project-identifier](#), the pid_generator shall check for collisions
across all [dic:specification](#)s, raising an error if a duplicate is found.

> verification_method: Test

> traceability: [HLR-PIPE-009](@)

#### LLR: Relation Type Constraint Filtering @LLR-043

Given an unresolved [dic:spec-relation](#) and the [dic:type-registry](#), [csu:relation-type-inferrer](#) shall
filter candidate relation types by [dic:relation-selector](#), `source_attribute`,
source `type_ref`, and target `type_ref` constraints.

> verification_method: Test

> traceability: [HLR-PIPE-010](@)

#### LLR: NULL Constraints Are Wildcards @LLR-044

When a candidate relation type has a NULL constraint, [csu:relation-type-inferrer](#) shall treat
it as a wildcard matching any value, adding 0 to the [dic:specificity-scoring](#) score.

> verification_method: Test

> traceability: [HLR-PIPE-010](@)

#### LLR: Specificity Tie Marks Ambiguity @LLR-045

When multiple candidates achieve equal highest [dic:specificity-scoring](#),
[csu:relation-type-inferrer](#) shall mark the [dic:spec-relation](#) as ambiguous.

> verification_method: Test

> traceability: [HLR-PIPE-010](@)

#### LLR: Same-Specification Target Preference @LLR-046

When resolving target candidates, [csu:resolution-queries](#) shall prefer targets in the same
[dic:specification](#) over cross-specification targets.

> verification_method: Test

> traceability: [HLR-PIPE-010](@)

---

### DD: SQLite as SpecIR Persistence Engine @DD-CORE-001

Selected SQLite as the persistence engine for the Specification Intermediate Representation.

> rationale: SQLite provides:
>
> - Zero-configuration embedded database requiring no server process
> - Single-file database portable across platforms (specir.db)
> - SQL-based query interface enabling declarative proof views and resolution logic
> - ACID transactions for reliable incremental builds with cache coherency
> - Built-in FTS5 for full-text search in the web application output
> - Mature Lua binding (lsqlite3) available in the Pandoc ecosystem

---

### DD: EAV Attribute Storage Model @DD-CORE-002

Selected Entity-Attribute-Value storage for dynamic object and float attributes.

> rationale: The EAV model enables runtime schema extension through model definitions:
>
> - Object types declare custom attributes in Lua modules without DDL changes
> - New models can add attributes by declaring them in type definitions
> - Typed columns provide SQL-level type safety while preserving EAV flexibility
> - Per-type pivot views (view_{type}_objects) generated dynamically from spec_attribute_types restore columnar access for queries
> - Alternative of wide tables rejected: column set unknown at schema creation time since models load after initialization

---

### DD: Five-Phase Pipeline Architecture @DD-CORE-003

Selected a five-phase sequential pipeline (INITIALIZE, ANALYZE, TRANSFORM, VERIFY, EMIT) for document processing.

> rationale: Five phases separate concerns and enable verification before output:
>
> - INITIALIZE parses AST into normalized relational IR before any resolution
> - ANALYZE resolves cross-references and infers types on the complete IR, not partial state
> - TRANSFORM renders content and materializes views with all references resolved
> - VERIFY runs proof views after TRANSFORM so it can check transform results (e.g., float render failures, view materialization)
> - EMIT generates output only after verification passes, preventing invalid documents
> - VERIFY-before-EMIT enables abort on error without wasting output generation time
> - Phase ordering is fixed; handler ordering within each phase is controlled by topological sort

---

### DD: Topological Sort for Handler Ordering @DD-CORE-004

Selected Kahn's algorithm with declarative prerequisite arrays for handler execution ordering within each pipeline phase.

> rationale: Declarative prerequisites with topological sort enable:
>
> - Handlers declare `prerequisites = {"handler_a", "handler_b"}` rather than manual sequence numbers
> - Only handlers implementing the current phase's hook participate in the sort
> - Alphabetical tie-breaking at equal dependency depth guarantees deterministic execution across runs
> - Cycle detection with error reporting prevents invalid configurations
> - New handlers (including model-provided handlers) integrate by declaring their prerequisites without modifying existing handlers
> - Alternative of priority numbers rejected: fragile when inserting new handlers between existing priorities
