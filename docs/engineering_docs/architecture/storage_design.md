## Storage Design

### FD: SpecIR Persistence and Cache Coherency @FD-003

> traceability: [SF-002](@)

**Allocation:** Realized by [CSC-002](@) (Database Persistence) through [CSU-012](@) (Data Manager) and [CSU-010](@) (Build Cache). The database schema is defined in [CSC-006](@) (DB Schema), queries in [CSC-005](@) (DB Queries), and materialized views in [CSC-007](@) (DB Views).

The [dic:intermediate-representation](#) persistence function manages the [dic:sqlite-database](#) database that stores all parsed
specification content and provides cache coherency for incremental builds. It encompasses
schema management, the [dic:eav-model](#) storage model, build caching, and output
caching.

**SQLite Persistence**: The data manager ([CSU-012](@)) wraps all database operations,
providing a query API over the SpecIR schema. The database file is created in the
project's output directory and persists across builds. Schema creation is executed inside
`DataManager.new()`, establishing all content and type tables. 

**SpecIR Schema**: The content schema ([CSU-013](@)) defines the core entity tables:

- `specifications` — Document-level containers with header AST and metadata
- `spec_objects` — Typed content blocks with AST, file position, and specification scope
- `spec_floats` — Embedded figures, listings, tables with render state
- `spec_views` — Materialized data views (TOC, LOF, traceability matrices)
- `spec_relations` — Links between objects with type inference results
- `spec_attribute_values` — EAV-model attribute storage for object and float properties

The type schema ([CSU-014](@)) defines the metamodel tables that describe valid types,
attribute definitions, and datatype constraints.

**EAV Attribute Model**: Attributes are stored as individual rows in `spec_attribute_values`
rather than as columns, enabling dynamic schema extension through model definitions.
Each attribute row references its parent entity (object or float), attribute definition,
and stores the value as text with type casting at query time.

**[dic:build-cache](#)**: The build cache ([CSU-010](@)) tracks document content hashes in the
`source_files` table. Before parsing a document, the engine computes its SHA1 hash and
compares against the stored value. Unchanged documents skip parsing entirely and reuse
their cached SpecIR state. To support incremental builds, the
`build_graph` table tracks include dependencies so that changes to included files also
trigger rebuilds. When the document hash matches, the Build Engine ([CSU-005](@)) queries
the `build_graph` table for all include dependencies recorded during the previous build.
It then computes a SHA1 hash for each include file via the Hash Utilities ([CSU-065](@)).
If an include file is missing, the hash returns nil, which forces a cache miss and a full
document rebuild. The resulting path-to-hash map is compared against the stored values; any
mismatch invalidates the cache and triggers reparsing of the root document.

**[dic:output-cache](#)**: The output cache tracks generated output files and their input hashes.
Before generating an output file, the emitter checks whether the input hash matches
the stored value. If current, the output generation is skipped. This provides incremental
output generation independent of the build cache.

**Component Interaction**

The storage subsystem is realized through four packages that separate runtime
operations from static definitions.

[csc:database-persistence](#) (Database Persistence) provides the runtime database layer. [csu:database-handler](#)
(Database Handler) wraps raw SQLite operations and connection management with DELETE journal
mode for single-file reliability. [csu:data-manager](#) (Data Manager) builds on the handler to provide the
high-level query API used by all pipeline phases — inserting spec entities during INITIALIZE,
updating references during ANALYZE, and reading assembled content during EMIT. [csu:build-cache](#)
(Build Cache) queries `source_files` and `build_graph` to detect changed documents via SHA1
comparison. [csu:output-cache](#) (Output Cache) tracks generated output files and their input hashes
to skip redundant generation. [csu:proof-view-definitions](#) (Proof View Definitions) materializes SQL proof
views at build time for the VERIFY phase.

[csc:db-schema](#) (DB Schema) defines the database structure through composable modules.
[csu:schema-aggregator](#) (Schema Aggregator) is the entry point, composing: [csu:content-schema](#) (Content Schema)
for the core SpecIR tables, [csu:type-system-schema](#) (Type System Schema) for attribute and datatype
definitions, [csu:build-schema](#) (Build Schema) for source file and dependency tracking, and
[csu:search-schema](#) (Search Schema) for FTS5 virtual tables.

[csc:db-queries](#) (DB Queries) mirrors the schema structure with composable query modules.
[csu:query-aggregator](#) (Query Aggregator) combines: [csu:content-queries](#) (Content Queries) for spec entity CRUD,
[csu:resolution-queries](#) (Resolution Queries) for cross-reference and relation resolution, [csu:build-queries](#)
(Build Queries) for cache and dependency lookups, [csu:type-queries](#) (Type Queries) for type
definitions and attribute constraints, and [csu:search-queries](#) (Search Queries) for FTS5 population
and search.

[csc:db-views](#) (DB Views) provides materialized SQL views over the SpecIR data. [csu:views-aggregator](#)
(Views Aggregator) composes: [csu:eav-pivot-views](#) (EAV Pivot Views) for pivoting attribute values into
typed columns, [csu:resolution-views](#) (Resolution Views) for joining relations with resolved targets,
and [csu:public-api-views](#) (Public API Views) for stable query interfaces used by pipeline handlers and
external tools.

```puml:fd-003-storage{caption="SpecIR Persistence and Cache Coherency"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Data Manager" as DB
participant "CSC-006 DB Schema" as SCH
participant "CSC-007 DB Views" as VW
participant "CSC-005 DB Queries" as QRY
participant "SQLite" as SQL

== Schema Initialization ==
E -> DB: DataManager.new(db_handler, log)
DB -> SCH: require Schema
SCH -> SCH: compose content.SQL\n+ types.SQL + build.SQL\n+ search.SQL
DB -> SQL: exec_sql(Schema.SQL)
note right: Creates all tables:\nspecifications, spec_objects,\nspec_floats, spec_views,\nspec_relations, spec_attribute_values,\nsource_files, build_graph,\nspec_*_types, spec_attribute_defs

== View Initialization ==
E -> VW: initialize_views(data)
VW -> SQL: CREATE VIEW (resolution views)
VW -> SQL: CREATE VIEW (public API views)
VW -> QRY: query spec_object_types
QRY --> VW: type definitions[]
loop for each non-composite object type
    VW -> VW: generate EAV pivot SQL
    VW -> SQL: CREATE VIEW view_{type}_objects
end

== Build Cache Check ==
E -> E: sha1(document_content)
E -> DB: query source_files(path)
DB -> QRY: build.document_hash_check
QRY -> SQL: SELECT sha1 FROM source_files
SQL --> E: cached_hash

alt hash matches
    E -> DB: query build_graph(root_path)
    DB -> QRY: build.include_dependencies
    QRY --> E: includes[]
    E -> E: verify include hashes
    alt all match
        E -> E: skip parsing (use cached IR)
    else include changed
        E -> E: reparse document
    end
else content changed
    E -> E: reparse document
end

== After Parse ==
E -> DB: INSERT/UPDATE spec entities
E -> DB: UPDATE source_files hash
E -> DB: UPDATE build_graph entries

== Output Cache ==
E -> DB: query output_cache(spec_id, format)
DB -> QRY: build.output_cache_check
alt output current
    E -> E: skip generation
else stale
    E -> E: generate output
    E -> DB: UPDATE output_cache
end
@enduml
```

#### LLR: DataManager Rollback Cancels Staged Inserts @LLR-DB-007-01

`DataManager.begin_transaction()` followed by facade insert calls
and `DataManager.rollback()` shall leave no persisted staged rows.

> verification_method: Test

> traceability: [HLR-STOR-001](@)

#### LLR: DataManager CRUD Facade Persists Canonical IR Rows @LLR-DB-007-02

DataManager facade methods (`insert_specification`,
`insert_object`, `insert_float`, `insert_relation`, `insert_view`,
`insert_attribute_value`, `query_all`, `query_one`, `execute`) shall persist
and retrieve canonical IR rows in content tables.

> verification_method: Test

> traceability: [HLR-STOR-001](@)

#### LLR: Attribute Casting Persists Typed Columns For Valid Pending Rows @LLR-DB-008-01

Attribute casting shall map raw attribute values to the correct
typed columns (`string_value`, `int_value`, `real_value`, `bool_value`,
`date_value`, `enum_ref`) and skip updates for invalid casts.

> verification_method: Test

> traceability: [HLR-STOR-002](@)

#### LLR: Build Cache Clean on Hash Match @LLR-047

Given a document path and its current SHA1 hash, [csu:build-cache](#)
`is_document_dirty()` shall query the [dic:build-cache](#) `source_files` table and
return `false` when the stored `sha1` matches.

> verification_method: Test

> traceability: [HLR-STOR-003](@)

#### LLR: Build Cache Dirty on Missing Entry @LLR-048

Given a document path not present in the [dic:build-cache](#) `source_files` table,
[csu:build-cache](#) `is_document_dirty()` shall return `true`.

> verification_method: Test

> traceability: [HLR-STOR-003](@)

#### LLR: Output Cache Stale on Hash Mismatch @LLR-049

Given a spec_id, output_path, and current [dic:processed-intermediate-representation](#) hash, [csu:output-cache](#)
`is_output_current()` shall return `false` when the stored `pir_hash` in the
[dic:output-cache](#) differs.

> verification_method: Test

> traceability: [HLR-STOR-004](@)

#### LLR: Output Cache Stale on Missing File @LLR-050

When the output file does not exist on disk, [csu:output-cache](#) `is_output_current()`
shall return `false` regardless of hash match.

> verification_method: Test

> traceability: [HLR-STOR-004](@)

#### LLR: Include-Aware Dirty Check @LLR-051

Given a root document path, [csu:build-cache](#) `is_document_dirty_with_includes()`
shall check both the root hash and all [dic:build-graph](#) `node_sha1` entries,
returning `true` if any differs.

> verification_method: Test

> traceability: [HLR-STOR-005](@)

#### LLR: Build Graph Refresh After Build @LLR-052

After a successful build, [csu:build-cache](#) and [csu:build-queries](#) `update_build_graph()`
shall delete old [dic:build-graph](#) rows for `root_path` and insert the
current include tree.

> verification_method: Test

> traceability: [HLR-STOR-005](@)

#### LLR: EAV Pivot View Naming @LLR-053

Given [dic:type-registry](#) `spec_object_types` entries, [csu:eav-pivot-views](#) shall generate
[dic:eav-model](#) pivot views named `view_{type_lower}_objects` with one column per
registered attribute.

> verification_method: Test

> traceability: [HLR-STOR-006](@)

#### LLR: No Pivot View for Composites @LLR-054

Given a [dic:composite-object-type](#) `spec_object_types` entry, [csu:eav-pivot-views](#) shall not
generate a pivot view.

> verification_method: Test

> traceability: [HLR-STOR-006](@)

---

### DD: Content-Addressed Build Caching @DD-CORE-007

Selected SHA1 content hashing for incremental build detection.

> rationale: Content-addressed hashing provides deterministic cache invalidation:
>
> - SHA1 of document content detects actual changes, ignoring timestamp-only modifications
> - Include dependency tracking via `build_graph` table ensures changes to included files trigger rebuilds
> - Missing include files force cache miss (hash returns nil), preventing stale IR state
> - Deferred cache updates (after successful pipeline execution) prevent stale entries on error
> - Output cache tracks generated files independently, enabling incremental output generation
> - Uses Pandoc's built-in `pandoc.sha1()` when available, falling back to `vendor/sha2.lua` in standalone mode
> - Alternative of file timestamps rejected: unreliable across platforms (git checkout, copy, WSL2 clock skew)


### DD: Dynamic SQL View Generation for EAV Pivots @DD-DB-002

Selected runtime-generated CREATE VIEW statements per object type to pivot EAV attributes into typed columns.

> rationale: Dynamic view generation bridges EAV flexibility with query usability:
>
> - Views generated after type loading, when attribute definitions are known
> - One view per non-composite object type (view_{type}_objects) with type-appropriate MAX(CASE) pivot expressions
> - Datatype-aware column selection (string_value for STRING, int_value for INTEGER, etc.)
> - External tools query familiar columnar views instead of raw EAV tables
> - Three-stage view initialization: resolution views first, public API views second, EAV pivots last
> - Alternative of application-layer pivoting rejected: pushes N+1 query patterns to every consumer
