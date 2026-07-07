## Audit & Integrity Design

### FD: Audit and Integrity @FD-006

> traceability: [SF-006](@)

**Allocation:** Realized by [CSC-001](@) (Core Runtime) and [CSC-020](@) (Default Analyze Queries) through [CSU-031](@) (Analyze Handler) and [CSU-065](@) (Hash Utilities).

The audit and integrity function ensures deterministic compilation, reproducible builds,
and audit trail integrity. It encompasses content-addressed hashing for incremental build
detection, structured logging for audit trails, and include dependency tracking for
proper cache invalidation.

**Include Hash Computation**: The engine ([CSU-005](@)) queries the `build_graph` table for known includes
from the previous build, then computes SHA1 hashes for each include file. Missing files
cause a cache miss (triggering a full rebuild). The resulting map of path-to-hash is
compared against stored values to detect changes. SHA1 hashing uses Pandoc's built-in
`pandoc.sha1()` when available, falling back to `vendor/sha2.lua` in standalone worker mode.

**Document Change Detection**: Each document's content is hashed and compared against the
hashes recorded as `build_graph` nodes (the root document is its own node, alongside its
includes). Unchanged documents (every node hash matching) skip parsing and reuse cached
[dic:intermediate-representation](#) state, providing significant performance improvement
for large projects.

**Structured Logging**: NDJSON (Newline-Delimited JSON) logging provides machine-parseable
audit trails with structured data (level, message, timestamp, context). Log level is
configurable via `config.logging.level` with environment override via `SPECCOMPILER_LOG_LEVEL`.
Levels: DEBUG, INFO, WARN, ERROR.

**Build Reproducibility**: Given identical source files (by content hash), project
configuration, and tool versions, the system produces identical outputs. Content-addressed
hashing of documents, includes, and the P-IR state ensures deterministic compilation.

**Verification Execution**: The Analyze Handler [CSU-031](@) executes in batch mode during
the ANALYZE phase. It iterates over all registered analyze queries,
querying each via the Data Manager [CSU-012](@). For each violation row returned, the
handler consults the Validation Policy [CSU-009](@) to determine the configured severity
level. Error-level violations are emitted as structured diagnostics via the Diagnostics
Collector [CSU-004](@). Violations at the ignore level are suppressed entirely. Each analyze query
enforces constraints declared by the type metamodel, ensuring that registered types
satisfy their validation rules.

After verification completes, the handler stores the verification result (error and
warning counts) in all pipeline contexts. The Pipeline Orchestrator [CSU-006](@) checks
for errors after ANALYZE and aborts before EMIT if any exist.

**Analyze Queries — Entity-Based Taxonomy**

Verification views follow the SpecIR 5-tuple: **S** (Specification), **O** (Object), **F** ([dic:float](#)), **R** (Relation), **V** (View). Each analyze query is identified by its `policy_key`.

*Specification Verification views (S)*

```list-table:tbl-verification-spec{caption="Specification analyze queries"}
> header-rows: 1
> aligns: l,l,l

* - Policy Key
  - View Name
  - Validates
* - `spec_missing_required`
  - view_spec_missing_required
  - Required spec attributes present
* - `spec_invalid_type`
  - view_spec_invalid_type
  - Specification type is valid
```

*Spec Object Verification views (O)*

```list-table:tbl-verification-object{caption="Spec object analyze queries"}
> header-rows: 1
> aligns: l,l,l

* - Policy Key
  - View Name
  - Validates
* - `missing_required`
  - view_object_missing_required
  - Required object attributes present
* - `cardinality_over`
  - view_object_cardinality_over
  - Attribute count <= max_occurs
* - `invalid_cast`
  - view_object_cast_failures
  - Attribute value casts to declared type
* - `invalid_enum`
  - view_object_invalid_enum
  - Enum value exists in enum_values
* - `invalid_date`
  - view_object_invalid_date
  - Date format is YYYY-MM-DD
* - `bounds_violation`
  - view_object_bounds_violation
  - Numeric values within min/max bounds
* - `object_duplicate_pid`
  - view_object_duplicate_pid
  - PID is globally unique
```

*Spec Float Verification views (F)*

```list-table:tbl-verification-float{caption="Spec float analyze queries"}
> header-rows: 1
> aligns: l,l,l

* - Policy Key
  - View Name
  - Validates
* - `float_orphan`
  - view_float_orphan
  - Float has a parent object
* - `float_duplicate_label`
  - view_float_duplicate_label
  - Float labels unique per specification
* - `float_render_failure`
  - view_float_render_failure
  - External render succeeded
* - `float_invalid_type`
  - view_float_invalid_type
  - Float type is registered
```

*Spec Relation Verification views (R)*

```list-table:tbl-verification-relation{caption="Spec relation analyze queries"}
> header-rows: 1
> aligns: l,l,l

* - Policy Key
  - View Name
  - Validates
* - `unresolved_relation`
  - view_relation_unresolved
  - Link target resolves
* - `dangling_relation`
  - view_relation_dangling
  - Target ref points to existing object
* - `ambiguous_relation`
  - view_relation_ambiguous
  - Float reference is unambiguous
```

**Component Interaction**

The audit subsystem is realized through core runtime components and the default verification
view package.

[csc:core-runtime](#) (Core Runtime) provides the verification infrastructure. [csu:build-engine](#) (Build
Engine) drives the build lifecycle and content-addressed hash computation. [csu:analyze-query-loader](#)
(Analyze Query Loader) discovers and loads analyze query modules from model directories, registering them with
the data manager for ANALYZE phase execution. [csu:validation-policy](#) (Validation Policy) maps analyze query
`policy_key` values to configured severity levels (error, warn, ignore) from `project.yaml`.
[csu:analyze-handler](#) (Analyze Handler) iterates over registered analyze queries during ANALYZE, querying each
via [csu:data-manager](#) (Data Manager) and emitting violations through [csu:diagnostics-collector](#) (Diagnostics
Collector). [csu:pipeline-orchestrator](#) (Pipeline Orchestrator) inspects diagnostics after ANALYZE and aborts
before EMIT if errors exist.

[csc:default-analyze-queries](#) (Default Analyze Queries) provides the baseline verification rules organized by the
SpecIR 5-tuple. Specification analyze queries: [csu:spec-missing-required](#) (Spec Missing Required) validates that
required specification attributes are present, and [csu:spec-invalid-type](#) (Spec Invalid Type) validates
that specification types are registered. Object analyze queries: [csu:object-missing-required](#) (Object Missing Required)
checks required object attributes, [csu:object-cardinality-over](#) (Object Cardinality Over) enforces max_occurs
limits, [csu:object-cast-failures](#) (Object Cast Failures) validates attribute type casts, [csu:object-invalid-enum](#) (Object
Invalid Enum) checks enum values against allowed sets, [csu:object-invalid-date](#) (Object Invalid Date)
validates YYYY-MM-DD date format, and [csu:object-bounds-violation](#) (Object Bounds Violation) checks numeric
bounds. Float analyze queries: [csu:float-orphan](#) (Float Orphan) detects floats without parent objects,
[csu:float-duplicate-label](#) (Float Duplicate Label) enforces label uniqueness per specification, [csu:float-render-failure](#)
(Float Render Failure) flags failed external renders, and [csu:float-invalid-type](#) (Float Invalid Type)
validates float type registration. Relation analyze queries: [csu:relation-unresolved](#) (Relation Unresolved) detects
links whose targets cannot be resolved, [csu:relation-dangling](#) (Relation Dangling) detects resolved
references pointing to nonexistent objects, and [csu:relation-ambiguous](#) (Relation Ambiguous) flags
ambiguous float references.

```puml:fd-006-audit{caption="Audit and Integrity: Build Caching and Verification"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Hash Utilities" as H
participant "CSU Analyze Query Loader" as PL
participant "CSU Analyze Handler" as VH
participant "CSU Validation\nPolicy" as VP
participant "CSU Data Manager" as DB

== Document Hash Check ==
E -> H: sha1_file(document_path)
H --> E: content_hash

E -> DB: SELECT node_path, node_sha1\nFROM build_graph WHERE root_path = :path
DB --> E: nodes[] (root + includes)

loop for each include node
    E -> H: sha1_file(node_path)
    H --> E: node_hash
end

alt root node present and every node hash matches
    E -> E: skip (use cached IR)
else node changed / missing / no root node
    E -> E: rebuild document
end

== After Rebuild ==
E -> DB: rewrite build_graph nodes\n(root self-node + includes)

== Analyze Query Loading ==
E -> PL: load_model("default")
PL -> PL: scan analyze_queries/*.lua
PL -> PL: register analyze queries by policy_key

E -> PL: load_model(template)
note right: Override/extend analyze queries\nby policy_key

E -> PL: create_views(data)
loop for each registered analyze query
    PL -> DB: exec_sql(analyze_query.sql)
    note right: CREATE VIEW {analyze_query.view}
end

== ANALYZE Phase ==
VH -> PL: get_analyze_queries()
PL --> VH: analyze_query_registry[]

loop for each analyze query
    VH -> DB: SELECT * FROM {analyze_query.view}
    DB --> VH: violation rows[]

    loop for each violation
        VH -> VP: get_level(analyze_query.policy_key)
        VP --> VH: severity

        alt level == "error"
            VH -> VH: diagnostics:error(violation)
        else level == "warn"
            VH -> VH: diagnostics:warn(violation)
        end
    end
end

VH -> VH: store verification_result\nin contexts
@enduml
```

#### LLR: Deferred Hash Update on Success @LLR-084

When build completes with no [dic:analyze-phase](#) errors, [csu:build-engine](#) shall rewrite
the [dic:build-graph](#) node hashes via [csu:build-cache](#); when errors are present,
hashes shall not be updated.

> verification_method: Test

> traceability: [HLR-AUDIT-001](@)

#### LLR: Cache Hit Skips Pipeline @LLR-085

When all [dic:build-graph](#) node hashes (root and includes) match current content,
[csu:build-engine](#) shall skip [dic:pipeline](#) processing and reuse cached [dic:intermediate-representation](#)
state.

> verification_method: Test

> traceability: [HLR-AUDIT-001](@)

#### LLR: Include Dependencies Recorded in Build Graph @LLR-086

During include expansion, [csu:include-expansion-filter](#) shall record `root_path`, `node_path`,
and `node_sha1` for each included file into the [dic:build-graph](#) table via
[csu:build-cache](#).

> verification_method: Test

> traceability: [HLR-AUDIT-002](@)

#### LLR: Circular Include Error Before Expansion @LLR-087

When an include path is already in the processed-file set, [csu:include-expansion-filter](#) shall
raise an error with the circular include chain path before performing any
expansion.

> verification_method: Test

> traceability: [HLR-AUDIT-002](@)

#### LLR: Diagnostic Record Structure @LLR-088

Given a `diagnostics:error(file, line, code, msg)` or `diagnostics:warn(...)`
call from any [dic:handler](#), [csu:diagnostics-collector](#) shall store a [dic:diagnostic-record](#)
record with `file` (path), `line` (int), `code` (string), and `msg` (string).

> verification_method: Test

> traceability: [HLR-AUDIT-003](@)

#### LLR: Diagnostic Code Domain Prefix Format @LLR-089

[dic:diagnostic-record](#) codes shall follow domain prefix + number format (e.g.,
`invalid_enum`, `dangling_relation`) enabling machine-parseable
classification via [csu:diagnostics-collector](#).

> verification_method: Test

> traceability: [HLR-AUDIT-003](@)

#### LLR: NDJSON Log Output Format @LLR-090

Given non-TTY output, [csu:logger](#) shall emit one [dic:newline-delimited-json](#) object per
line with fields `level`, `message`, `timestamp`, and optional context.

> verification_method: Test

> traceability: [HLR-AUDIT-004](@)

#### LLR: NO_COLOR Compliance @LLR-091

Given TTY output with `NO_COLOR` environment variable set, [csu:logger](#) shall
suppress ANSI color codes in console mode.

> verification_method: Test

> traceability: [HLR-AUDIT-004](@)

#### LLR: Deterministic Float Numbering by File Sequence @LLR-092

[csu:float-numbering](#) shall determine [dic:spec-float](#) numbering solely by `file_seq`
ordering, which is stable across builds for identical input.

> verification_method: Test

> traceability: [HLR-AUDIT-005](@)

#### LLR: Hash-Only Cache Invalidation @LLR-093

[csu:build-cache](#) shall base [dic:build-cache](#) dirty checks solely on SHA1 content hashes,
never on filesystem timestamps or mtime.

> verification_method: Test

> traceability: [HLR-AUDIT-005](@)
