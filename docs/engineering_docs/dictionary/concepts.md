## System Concepts

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

A **Lua module** generating data for chart injection.

> description:
>
> **Purpose:** Produces structured data that can be injected into chart floats.
>
> **Implementation:** Lua scripts that query database and return chart-compatible data structures.

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

A **numbered element** (table, figure, diagram) with caption and cross-reference. See [SpecIR-03](@) for full definition.

### DIC: External Renderer @TERM-34

**Subprocess-based rendering** for types like PLANTUML, CHART.

> description:
>
> **Purpose:** Delegates rendering to external tools via subprocess execution.
>
> **Examples:** PlantUML JAR for diagrams, chart libraries for data visualization.

### DIC: Handler @TERM-16

A **modular component** that processes specific content types through pipeline phases.

> description:
>
> **Purpose:** Encapsulates processing logic for a content type across all pipeline phases.
>
> **Structure:** Implements phase methods (initialize, analyze, verify, transform, emit) for its content type.

### DIC: INITIALIZE Phase @TERM-19

The **first phase** in the pipeline that parses AST and populates IR containers.

> description:
>
> **Purpose:** Parses markdown AST and populates intermediate representation containers.
>
> **Position:** First phase, entry point for document processing.

### DIC: Model @TERM-33

A **collection of type definitions**, handlers, and styles for a domain.

> description:
>
> **Purpose:** Bundles related type definitions, handlers, and styling for specific documentation domains.
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

**System that discovers and loads** type handlers from model directories.

> description:
>
> **Purpose:** Dynamically discovers and instantiates type handlers from model definitions.
>
> **Implementation:** Scans model directories for handler definitions and registers them.

### DIC: Type Registry @TERM-26

**Database tables** (spec_*_types) storing type definitions.

> description:
>
> **Purpose:** Stores type definitions including attributes, aliases, and validation rules.
>
> **Tables:** spec_object_types, spec_float_types, spec_attribute_types, etc.

### DIC: VERIFY Phase @TERM-21

The **fourth phase** in the pipeline that validates content via proof views.

> description:
>
> **Purpose:** Validates document content using proof views and constraint checking.
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

### DIC: Proof View @TERM-PROOF

A **SQL query** that validates data integrity constraints during the VERIFY phase.

> term: Proof View

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
> **Purpose:** Defines the schema, validation rules, and rendering behavior for a category of elements.
>
> **Categories:** Object types (HLR, SECTION), float types (FIGURE, TABLE), relation types (TRACES_TO), view types (TOC, LOF).
>
> **Registration:** Types are loaded from model directories and stored in the type registry.

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
