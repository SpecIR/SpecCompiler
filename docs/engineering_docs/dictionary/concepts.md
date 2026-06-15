## System Concepts

### DIC: CommonSpec @TERM-COMMONSPEC

A **structured Markdown language** for authoring typed, traceable specifications.

> term: CommonSpec

> domain: Core

> description:
>
> **Purpose:** Defines the input language for SpecCompiler. Extends standard Markdown (CommonMark) with six constructs: specifications, spec objects, spec floats, attributes, spec relations, and spec views.
>
> **Architecture:** CommonSpec (language) compiles into SpecIR (intermediate representation) via SpecCompiler (compiler).
>
> **Specification:** See the CommonSpec Language Specification (`docs/commonspec/`) for the formal definition.

### DIC: SpecIR @TERM-SPECIR

A **typed relational intermediate representation** for specifications, stored in SQLite.

> term: Specification Intermediate Representation

> acronym: SpecIR

> domain: Core

> description:
>
> **Purpose:** Provides a portable, queryable storage format for specification data. Compilation target for CommonSpec and interchange format for other tools (ReqIF, DOORS CSV, SQL).
>
> **Schema:** Two core layers: Type System tables (metamodel) and Content tables (data). Build infrastructure and FTS tables are not part of the SpecIR standard.
>
> **Specification:** See the SpecIR Schema Specification (`docs/specir/`) for the formal definition.

### DIC: ANALYZE Phase @TERM-20

The **second phase** in the pipeline that resolves references and infers types.

> description:
>
> **Purpose:** Resolves cross-references between spec objects and infers missing type information.
>
> **Position:** Second phase after INITIALIZE, before TRANSFORM.

### DIC: Build Cache @TERM-30

**SHA1 hashes** for detecting document changes.

> description:
>
> **Purpose:** Stores content hashes to detect which documents have changed since last build.
>
> **Implementation:** Compares current file hash against cached hash to skip unchanged files.

### DIC: Counter Group @TERM-28

**Float types** sharing a numbering sequence.

> description:
>
> **Purpose:** Groups related float types to share sequential numbering.
>
> **Example:** FIG and DIAGRAM types may share a counter, producing Figure 1, Figure 2, etc.

### DIC: CSC (Computer Software Component) @TERM-36

A **MIL-STD-498 architectural decomposition element** representing a subsystem, layer, package, or service.

> description:
>
> **Purpose:** Groups software units into higher-level structural components for design allocation.
>
> **Examples:** `src/core`, `src/db`, `src/infra`.

### DIC: CSU (Computer Software Unit) @TERM-37

A **MIL-STD-498 implementation decomposition element** representing a source file or code unit.

> description:
>
> **Purpose:** Captures file-level implementation units allocated to functional descriptions.
>
> **Examples:** `src/core/pipeline.lua`, `src/db/manager.lua`.

### DIC: Data View @TERM-35

A **view descriptor** whose `dataset` data hook generates data for chart injection.

> description:
>
> **Purpose:** Produces structured data that can be injected into chart floats.
>
> **Implementation:** A `dataset` DATA hook receives a frozen data context (reading `subject.params`) and returns a `{ source / data / links }` dataset. The descriptor is resolved from `models/{requested}/types/views/{view}` with fallback to `models/default/types/views/{view}`.

### DIC: EAV Model @TERM-EAV

**Entity-Attribute-Value** pattern for typed attribute storage.

> description:
>
> **Purpose:** Flexible schema for storing typed attributes on spec objects.
>
> **Structure:** Entity (spec object), Attribute (key name), Value (typed content).

### DIC: EMIT Phase @TERM-23

The **final phase** in the pipeline that assembles and outputs documents.

> description:
>
> **Purpose:** Assembles transformed content and writes final output documents.
>
> **Position:** Final phase after VERIFY.

### DIC: Float @TERM-04

A **numbered element** (table, figure, diagram) with caption and cross-reference. See [dic:spec-float](#) for full definition.

### DIC: External Renderer @TERM-34

**Subprocess-based rendering** for types like PLANTUML, CHART.

> description:
>
> **Purpose:** Delegates rendering to external tools via subprocess execution.
>
> **Examples:** PlantUML JAR for diagrams, chart libraries for data visualization.

### DIC: Handler @TERM-16

A **named hook** that a type descriptor contributes to the pipeline, indexed by the host engine and dispatched by capability rather than declared on a `M.handler` surface.

> description:
>
> **Purpose:** Encapsulates processing logic for a content type. Behaviour lives only under a descriptor's `hooks` table; the host classifies each hook by name and indexes it into the `(kind, id) -> hook` map.
>
> **Structure:** Two kinds of contributions, both keyed by hook name:
>
> - **Phase participation** — `on_<phase>` functions (`on_initialize`, `on_analyze`, `on_transform`, `on_verify`, `on_emit`) declared in `hooks` beside the behavior hooks; the host synthesizes them into `pipeline:register_handler` under the derived name `<lower(id)>_handler`, ordered via `schema.phase_prerequisites`. Each runs once per phase with full pipeline context.
> - **Per-item hooks** — RENDER hooks (`render`, `render_block`, `render_link`, `message`) and DATA hooks (`dataset`, `build_block`, `transform`, `resolve`, `prepare_task`, `handle_result`). The hook NAME selects one of two context tiers (a frozen render ctx or a frozen data ctx) and the return type the hook owes. Consumers resolve them via `get_hook_inherited`, which walks the `extends` chain.

### DIC: INITIALIZE Phase @TERM-19

The **first phase** in the pipeline that parses AST and populates IR containers.

> description:
>
> **Purpose:** Parses markdown AST and populates intermediate representation containers.
>
> **Position:** First phase, entry point for document processing.

### DIC: Model @TERM-33

A **collection of type descriptors** and styles for a domain, overlaid onto the `default` model by the host engine.

> description:
>
> **Purpose:** Bundles related type descriptors (each carrying its own `hooks`) and styling for specific documentation domains. The host overlays `default` then each model later-wins-by-id, so a model overrides only the type ids it redefines.
>
> **Examples:** SRS model for software requirements, HRS model for hardware requirements.

### DIC: Output Cache @TERM-31

**Timestamps** for incremental output generation.

> description:
>
> **Purpose:** Tracks when outputs were last generated to enable incremental builds.
>
> **Implementation:** Compares source modification time against cached output timestamp.

### DIC: Phase @TERM-17

A **distinct stage** in document processing with specific responsibilities.

> description:
>
> **Purpose:** Separates document processing into well-defined sequential stages.
>
> **Phases:** INITIALIZE, ANALYZE, TRANSFORM, VERIFY, EMIT.

### DIC: Pipeline @TERM-15

The **5-phase processing system** (INITIALIZE -> ANALYZE -> TRANSFORM -> VERIFY -> EMIT).

> description:
>
> **Purpose:** Orchestrates document processing through sequential phases.
>
> **Flow:** Each phase completes for all handlers before the next phase begins.

### DIC: Prerequisites @TERM-24

**Handler dependencies** that determine execution order.

> description:
>
> **Purpose:** Declares which handlers must complete before a given handler can execute.
>
> **Usage:** Handlers declare prerequisites to ensure data dependencies are satisfied.

### DIC: Topological Sort @TERM-25

**Kahn's algorithm** for ordering handlers by prerequisites.

> description:
>
> **Purpose:** Determines valid execution order for handlers based on dependencies.
>
> **Algorithm:** Uses Kahn's algorithm to produce a topologically sorted handler sequence.

### DIC: TRANSFORM Phase @TERM-22

The **third phase** in the pipeline that materializes views and rewrites content.

> description:
>
> **Purpose:** Materializes database views into content and applies content transformations.
>
> **Position:** Third phase after ANALYZE, before VERIFY.

### DIC: Type Alias @TERM-27

**Alternative syntax identifier** for a type (e.g., "csv" -> "TABLE").

> description:
>
> **Purpose:** Provides shorthand or alternative names for types.
>
> **Example:** `csv` is an alias for the TABLE type in float definitions.

### DIC: Type Loader @TERM-38

The **host engine** (`src/contract/registry.lua`) that overlays models and registers their type descriptors.

> description:
>
> **Purpose:** Discovers each model's type descriptors and registers them with the SpecIR type tables, the data manager, and the pipeline.
>
> **Implementation:** Overlays the `default` model then each requested model (later-wins-by-id; resolved repo-bundled under `SPECCOMPILER_HOME/models/{model}` then cwd, no out-of-tree path). For each `models/{model}/types/{category}/` file it loads the single returned descriptor `{ kind, schema, [hooks] }`, validates it (known `kind`, present `schema.id`, each hook valid for the kind, no behaviour on top-level keys), emits the type row, and eager-indexes each hook into a `(kind, id) -> hook` map read via `get_hook` / `get_hook_inherited` (which walks the `extends` chain). `host:finalize()` then propagates inherited attributes, creates the verification SQL views, and asserts required hooks.

### DIC: Type Registry @TERM-26

**Database tables** (spec_*_types) storing type definitions.

> description:
>
> **Purpose:** Stores type definitions including attributes, aliases, and validation rules.
>
> **Tables:** spec_object_types, spec_float_types, spec_attribute_types, etc.

### DIC: VERIFY Phase @TERM-21

The **fourth phase** in the pipeline that validates content via verification views.

> description:
>
> **Purpose:** Validates document content using verification views and constraint checking.
>
> **Position:** Fourth phase after TRANSFORM, before EMIT.

### DIC: Abstract Syntax Tree @TERM-AST

The **tree representation** of document structure produced by Pandoc.

> term: Abstract Syntax Tree

> acronym: AST

> domain: Core

> description:
>
> **Purpose:** Represents document structure as a hierarchical tree of elements.
>
> **Source:** Pandoc parses Markdown and produces JSON AST.
>
> **Usage:** Handlers walk the AST to extract spec objects, floats, and relations.

### DIC: Full-Text Search @TERM-FTS

**FTS5 virtual tables** enabling search across specification content.

> term: Full-Text Search

> acronym: FTS

> domain: Database

> description:
>
> **Purpose:** Indexes specification text for fast full-text search queries.
>
> **Implementation:** SQLite FTS5 virtual tables populated during EMIT phase.
>
> **Usage:** Web application uses FTS for search functionality.

### DIC: High-Level Requirement @TERM-HLR

A **top-level functional or non-functional requirement** that captures what the system must do or satisfy.

> term: High-Level Requirement

> acronym: HLR

> domain: Core

> description:
>
> **Purpose:** Defines system-level requirements that guide design and implementation.
>
> **Traceability:** HLRs trace to verification cases (VC) and are realized by functional descriptions (FD).

### DIC: Intermediate Representation @TERM-IR

The **database-backed representation** of parsed document content.

> term: Intermediate Representation

> acronym: IR

> domain: Core

> description:
>
> **Purpose:** Stores parsed specification content in queryable form.
>
> **Storage:** SQLite database with spec_objects, spec_floats, spec_relations tables.
>
> **Lifecycle:** Populated during INITIALIZE, queried and modified through remaining phases.

### DIC: Project Identifier @TERM-PID

A **unique identifier** assigned to spec objects for cross-referencing (e.g., `@REQ-001`).

> term: Project Identifier

> acronym: PID

> domain: Core

> description:
>
> **Purpose:** Provides unique, human-readable identifiers for traceability and cross-referencing.
>
> **Syntax:** Written as `@PID` in header text (e.g., `## HLR: Requirement Title @REQ-001`).
>
> **Auto-generation:** PIDs can be auto-generated from type prefix and sequence number.

### DIC: Verification View @TERM-VERIFICATIONVIEW

A **SQL query** that validates data integrity constraints during the VERIFY phase.

> term: Verification View

> acronym: -

> domain: Core

> description:
>
> **Purpose:** Defines validation rules as SQL queries that detect specification errors.
>
> **Execution:** Run during the VERIFY phase; violations are reported as diagnostics.
>
> **Examples:** Missing required attributes, unresolved relations, cardinality violations.

### DIC: SQLite Database @TERM-SQLITE

The **embedded database engine** storing the IR and build cache.

> term: SQLite Database

> acronym: -

> domain: Database

> description:
>
> **Purpose:** Provides persistent, portable storage for the intermediate representation.
>
> **Benefits:** Single-file storage, ACID transactions, SQL query capability.
>
> **Usage:** All pipeline phases read/write to SQLite via the database manager.

### DIC: Traceable Object @TERM-TRACEABLE

A **specification object** that participates in traceability relationships.

> term: Traceable Object

> acronym: -

> domain: Core

> description:
>
> **Purpose:** Base type for objects that can be linked via traceability relations.
>
> **Types:** Any spec object type registered in the model (e.g., HLR, LLR, SECTION).
>
> **Relations:** Model-defined relation types (e.g., XREF_FIGURE, XREF_CITATION) inferred by specificity matching.

### DIC: Type @TERM-TYPE

A **category definition** that governs behavior for objects, floats, relations, or views.

> term: Type

> acronym: -

> domain: Core

> description:
>
> **Purpose:** Defines the schema, validation rules, and `hooks` behaviour for a category of elements.
>
> **Categories:** Object types (HLR, SECTION), float types (FIGURE, TABLE), relation types (TRACES_TO), view types (TOC, LOF).
>
> **Registration:** Each type is one descriptor (`{ kind, schema, hooks }`) loaded from a model's category directory, validated by the host engine, and emitted into the type registry.

### DIC: Verification Case @TERM-VC

A **test specification** that verifies a requirement or set of requirements.

> term: Verification Case

> acronym: VC

> domain: Core

> description:
>
> **Purpose:** Defines how requirements are verified through test procedures and expected results.
>
> **Traceability:** VCs trace to HLRs via `traceability` attribute links.
>
> **Naming:** VC PIDs follow the pattern `VC-{category}-{seq}` (e.g., `VC-PIPE-001`).

### DIC: Composite Object Type @TERM-COMPOSITE

A **spec object type** whose instances receive hierarchical PIDs qualified by the parent specification PID.

> term: Composite Object Type

> domain: Core

> description:
>
> **Purpose:** Distinguishes object types that represent document structure (e.g., SECTION) from traceable types that receive standalone PIDs (e.g., HLR, VC).
>
> **PID behavior:** Composite objects get hierarchical PIDs derived from the specification PID (e.g., `SRS-sec1.2.3`). Non-composite objects get independent PIDs from their `pid_prefix` and `pid_format` (e.g., `HLR-001`).
>
> **Configuration:** Set via `is_composite = true` in the descriptor's `schema`.

### DIC: Relation Selector @TERM-SELECTOR

The **URL scheme portion** of a Markdown link that drives relation type inference.

> term: Relation Selector

> domain: Core

> description:
>
> **Purpose:** Identifies what kind of relation a Markdown link represents, enabling type-driven inference.
>
> **Selectors:** `@` (PID reference, e.g., `[HLR-001](@)`), `#` (label reference, e.g., `[fig:diagram](#)`), `@cite` (bibliographic citation).
>
> **Configuration:** Each relation type declares a `link_selector` value in `spec_relation_types`. Selectors are model-defined, not hardcoded.

### DIC: Specificity Scoring @TERM-SPECIFICITY

The **constraint-matching score** used to select the best relation type during type inference.

> term: Specificity Scoring

> domain: Core

> description:
>
> **Purpose:** Resolves ambiguity when multiple relation types match a given link by selecting the most specific type.
>
> **Algorithm:** Each non-NULL constraint match across four dimensions (selector, source_attribute, source_type, target_type) adds one point. The highest total score wins. Ties mark the relation as ambiguous.
>
> **Example:** A relation type with constraints on selector + source_type + target_type (score 3) wins over one with only selector (score 1).

### DIC: Processed Intermediate Representation @TERM-PIR

The **complete specification state** after all pipeline phases have executed, captured as a hash for output cache invalidation.

> term: Processed Intermediate Representation

> acronym: P-IR

> domain: Core

> description:
>
> **Purpose:** Provides a single hash that represents the fully processed state of a specification, including all resolved relations, materialized views, and transformed content.
>
> **Usage:** The output cache stores the P-IR hash alongside each generated output file. When rebuilding, the system compares the current P-IR hash to the cached hash to determine if output regeneration is needed.
>
> **Distinction:** Unlike the build cache (which tracks source file hashes), the P-IR hash captures the post-processing state, detecting changes from cross-document operations.

### DIC: Newline-Delimited JSON @TERM-NDJSON

A **text format** where each line is a valid JSON object, used for structured log output.

> term: Newline-Delimited JSON

> acronym: NDJSON

> domain: Infrastructure

> description:
>
> **Purpose:** Provides machine-parseable structured logging suitable for CI/CD log aggregation and filtering with tools like `jq`.
>
> **Format:** One JSON object per line with fields: `level`, `message`, `timestamp`, and optional context fields.
>
> **Usage:** The logger emits NDJSON when output is not connected to a TTY (e.g., piped to a file or running in CI).

### DIC: Validation Policy @TERM-VALIDATIONPOLICY

A **configuration mapping** from verification view `policy_key` to severity level, controlling which violations are reported and at what severity.

> term: Validation Policy

> domain: Core

> description:
>
> **Purpose:** Allows projects to control validation strictness by mapping each verification view to a severity level.
>
> **Severity levels:** `error` (blocks output generation), `warn` (reported but build continues), `ignore` (suppressed).
>
> **Configuration:** Set in the `validation:` section of `project.yaml` (e.g., `traceability_hlr_to_vc: warn`).
>
> **Default:** When a policy_key is not configured, the system applies its built-in default severity.

### DIC: Diagnostic Record @TERM-DIAGNOSTIC

A **structured error or warning record** emitted by [TERM-16](@)s during [TERM-15](@) processing.

> term: Diagnostic Record

> domain: Core

> description:
>
> **Purpose:** Provides machine-parseable and human-readable feedback on specification errors and warnings throughout all pipeline phases.
>
> **Fields:** Each record contains `file` (source path), `line` (source line number), `code` (stable diagnostic key, usually the verification view `policy_key`, e.g., `dangling_relation`), and `msg` (human-readable description).
>
> **Severity:** Errors trigger abort after [TERM-21](@) phase; warnings are reported but do not block output generation.

### DIC: Build Graph @TERM-BUILDGRAPH

A **dependency tracking structure** recording include file hierarchies for incremental rebuild support.

> term: Build Graph

> domain: Database

> description:
>
> **Purpose:** Tracks which files are included by each root document, enabling change detection across include hierarchies.
>
> **Storage:** Stored in the `build_graph` table with columns `root_path` (the including document), `node_path` (the included file), and `node_sha1` (content hash at build time).
>
> **Usage:** Queried by [TERM-30](@) `is_document_dirty_with_includes()` to determine if any included file has changed since the last successful build.

### DIC: Placeholder Block @TERM-PLACEHOLDERBLOCK

A **CodeBlock marker** inserted during document assembly for deferred [SpecIR-03](@) and [SpecIR-06](@) resolution.

> term: Placeholder Block

> domain: Pipeline

> description:
>
> **Purpose:** Marks positions in the assembled Pandoc document where floats and views will be substituted during the [TERM-23](@) phase.
>
> **Mechanism:** During assembly, [CSU-034](@) inserts CodeBlock elements at the correct `file_seq` positions. Downstream handlers ([CSU-035](@) for floats, [CSU-036](@) for views) match these placeholders by label and replace them with rendered content.
>
> **Lifecycle:** Created during assembly, consumed during float/view emission, never present in final output.
