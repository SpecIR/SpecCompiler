## Audit & Integrity Design

### FD: Audit and Integrity @FD-006

> traceability: [SF-006](@)

**Allocation:** Realized by [CSC-001](@) (Core Runtime) and [CSC-020](@) (Default Proof Views) through [CSU-031](@) (Verify Handler) and [CSU-065](@) (Hash Utilities).

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
`source_files` table. Unchanged documents (same content hash and include hashes) skip
parsing and reuse cached [TERM-IR](@) state, providing significant performance improvement
for large projects.

**Structured Logging**: NDJSON (Newline-Delimited JSON) logging provides machine-parseable
audit trails with structured data (level, message, timestamp, context). Log level is
configurable via `config.logging.level` with environment override via `SPECCOMPILER_LOG_LEVEL`.
Levels: DEBUG, INFO, WARN, ERROR.

**Build Reproducibility**: Given identical source files (by content hash), project
configuration, and tool versions, the system produces identical outputs. Content-addressed
hashing of documents, includes, and the P-IR state ensures deterministic compilation.

**Verification Execution**: The Verify Handler [CSU-031](@) executes in batch mode during
the VERIFY phase. It iterates over all registered proof views,
querying each via the Data Manager [CSU-012](@). For each violation row returned, the
handler consults the Validation Policy [CSU-009](@) to determine the configured severity
level. Error-level violations are emitted as structured diagnostics via the Diagnostics
Collector [CSU-004](@). Violations at the ignore level are suppressed entirely. Each proof view
enforces constraints declared by the type metamodel, ensuring that registered types
satisfy their validation rules.

After verification completes, the handler stores the verification result (error and
warning counts) in all pipeline contexts. The Pipeline Orchestrator [CSU-006](@) checks
for errors after VERIFY and aborts before EMIT if any exist.

**Proof Views — Entity-Based Taxonomy**

Proof views follow the SpecIR 5-tuple: **S** (Specification), **O** (Object), **F** ([TERM-04](@)), **R** (Relation), **V** (View). Each proof is identified by its `policy_key`.

*Specification Proofs (S)*

| Policy Key | View Name | Validates |
|------------|-----------|-----------|
| `spec_missing_required` | view_spec_missing_required | Required spec attributes present |
| `spec_invalid_type` | view_spec_invalid_type | Specification type is valid |

*Spec Object Proofs (O)*

| Policy Key | View Name | Validates |
|------------|-----------|-----------|
| `object_missing_required` | view_object_missing_required | Required object attributes present |
| `object_cardinality_over` | view_object_cardinality_over | Attribute count <= max_occurs |
| `object_cast_failures` | view_object_cast_failures | Attribute value casts to declared type |
| `object_invalid_enum` | view_object_invalid_enum | Enum value exists in enum_values |
| `object_invalid_date` | view_object_invalid_date | Date format is YYYY-MM-DD |
| `object_bounds_violation` | view_object_bounds_violation | Numeric values within min/max bounds |
| `object_duplicate_pid` | view_object_duplicate_pid | PID is globally unique |

*Spec Float Proofs (F)*

| Policy Key | View Name | Validates |
|------------|-----------|-----------|
| `float_orphan` | view_float_orphan | Float has a parent object |
| `float_duplicate_label` | view_float_duplicate_label | Float labels unique per specification |
| `float_render_failure` | view_float_render_failure | External render succeeded |
| `float_invalid_type` | view_float_invalid_type | Float type is registered |

*Spec Relation Proofs (R)*

| Policy Key | View Name | Validates |
|------------|-----------|-----------|
| `relation_unresolved` | view_relation_unresolved | Link target resolves |
| `relation_dangling` | view_relation_dangling | Target ref points to existing object |
| `relation_ambiguous` | view_relation_ambiguous | Float reference is unambiguous |

*Spec View Proofs (V)*

| Policy Key | View Name | Validates |
|------------|-----------|-----------|
| `view_materialization_failure` | view_view_materialization_failure | View materialization succeeded |

**Component Interaction**

The audit subsystem is realized through core runtime components and the default proof
view package.

[csc:core-runtime](#) (Core Runtime) provides the verification infrastructure. [csu:build-engine](#) (Build
Engine) drives the build lifecycle and content-addressed hash computation. [csu:proof-loader](#) (Proof
Loader) discovers and loads proof view modules from model directories, registering them with
the data manager for VERIFY phase execution. [csu:validation-policy](#) (Validation Policy) maps proof
`policy_key` values to configured severity levels (error, warn, ignore) from `project.yaml`.
[csu:verify-handler](#) (Verify Handler) iterates over registered proof views during VERIFY, querying each
via [csu:data-manager](#) (Data Manager) and emitting violations through [csu:diagnostics-collector](#) (Diagnostics
Collector). [csu:pipeline-orchestrator](#) (Pipeline Orchestrator) inspects diagnostics after VERIFY and aborts
before EMIT if errors exist.

[csc:default-proof-views](#) (Default Proof Views) provides the baseline verification rules organized by the
SpecIR 5-tuple. Specification proofs: [csu:spec-missing-required](#) (Spec Missing Required) validates that
required specification attributes are present, and [csu:spec-invalid-type](#) (Spec Invalid Type) validates
that specification types are registered. Object proofs: [csu:object-missing-required](#) (Object Missing Required)
checks required object attributes, [csu:object-cardinality-over](#) (Object Cardinality Over) enforces max_occurs
limits, [csu:object-cast-failures](#) (Object Cast Failures) validates attribute type casts, [csu:object-invalid-enum](#) (Object
Invalid Enum) checks enum values against allowed sets, [csu:object-invalid-date](#) (Object Invalid Date)
validates YYYY-MM-DD date format, and [csu:object-bounds-violation](#) (Object Bounds Violation) checks numeric
bounds. Float proofs: [csu:float-orphan](#) (Float Orphan) detects floats without parent objects,
[csu:float-duplicate-label](#) (Float Duplicate Label) enforces label uniqueness per specification, [csu:float-render-failure](#)
(Float Render Failure) flags failed external renders, and [csu:float-invalid-type](#) (Float Invalid Type)
validates float type registration. Relation proofs: [csu:relation-unresolved](#) (Relation Unresolved) detects
links whose targets cannot be resolved, [csu:relation-dangling](#) (Relation Dangling) detects resolved
references pointing to nonexistent objects, and [csu:relation-ambiguous](#) (Relation Ambiguous) flags
ambiguous float references. View proofs: [csu:view-materialization-failure](#) (View Materialization Failure) detects
failed view computations.

```puml:fd-006-audit{caption="Audit and Integrity: Build Caching and Verification"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Hash Utilities" as H
participant "CSU Proof Loader" as PL
participant "CSU Verify Handler" as VH
participant "CSU Validation\nPolicy" as VP
participant "CSU Data Manager" as DB

== Document Hash Check ==
E -> H: sha1_file(document_path)
H --> E: content_hash

E -> DB: SELECT sha1 FROM source_files\nWHERE path = :path
DB --> E: cached_hash

alt content_hash == cached_hash
    E -> E: check include hashes
    E -> DB: SELECT * FROM build_graph\nWHERE root_path = :path
    DB --> E: includes[]

    loop for each include
        E -> H: sha1_file(include_path)
        H --> E: include_hash
    end

    alt all include hashes match
        E -> E: skip (use cached IR)
    else include changed
        E -> E: rebuild document
    end
else content changed
    E -> E: rebuild document
end

== After Rebuild ==
E -> DB: UPDATE source_files SET sha1
E -> DB: UPDATE build_graph entries

== Proof Loading ==
E -> PL: load_model("default")
PL -> PL: scan proofs/*.lua
PL -> PL: register proofs by policy_key

E -> PL: load_model(template)
note right: Override/extend proofs\nby policy_key

E -> PL: create_views(data)
loop for each registered proof
    PL -> DB: exec_sql(proof.sql)
    note right: CREATE VIEW {proof.view}
end

== VERIFY Phase ==
VH -> PL: get_proofs()
PL --> VH: proof_registry[]

loop for each proof view
    VH -> DB: SELECT * FROM {proof.view}
    DB --> VH: violation rows[]

    loop for each violation
        VH -> VP: get_level(proof.policy_key)
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
