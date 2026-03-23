# SpecIR: Specification Intermediate Representation

> version: 1.0

> date: 2026-03-22

## INDEX

`toc:`

## Introduction

### What is SpecIR?

**SpecIR** is a typed relational intermediate representation for specifications, stored in SQLite. It is the compilation target for CommonSpec and serves as a universal interchange format for specification data.

Any tool can read and write a SpecIR database. CommonSpec is one input format; ReqIF, DOORS CSV, or direct SQL are others. SpecCompiler is the reference compiler that produces SpecIR from CommonSpec, but the IR is not tied to any single tool.

### Design Goals

**Portable.** A single `.db` file contains the complete specification state. Copy it, query it with any SQLite client, or serve it via a web application.

**Typed.** The schema enforces a type system: every object, float, relation, and view references a declared type. Proof views express structural constraints as SQL queries.

**Queryable.** Standard SQL gives immediate access to traceability matrices, coverage reports, orphan detection, and custom dashboards --- no export step required.

**Interoperable.** SpecIR is the bridge between formats. Import from ReqIF, edit in CommonSpec, export to DOCX --- SpecIR is the common ground.

### Schema Layers

The SpecIR database contains three layers of tables:

1. **Type System** --- defines the metamodel (what types of objects, floats, relations, and views can exist). Populated from model definitions.
2. **Content** --- stores actual specification data (requirements, tests, figures, traceability links). Populated by the compiler or by importers.
3. **Tooling** (non-core) --- build caches, full-text search indexes, and output tracking. These are SpecCompiler implementation details and are **not part of the SpecIR specification**.

Only layers 1 and 2 constitute the SpecIR standard. External tools reading or writing SpecIR should ignore layer 3 tables.

## Core Schema: Type System

The type system tables define the metamodel. They answer the question: "What kinds of things can exist in this specification?"

**Authoritative source:** `src/db/schema/types.lua`

### spec_object_types

Defines types of spec objects (e.g., HLR, LLR, VC, SECTION).

```list-table:tbl-object-types{caption="spec_object_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique type code (e.g. HLR)
long_name,TEXT NOT NULL UNIQUE,Human-readable name
description,TEXT,Documentation
extends,TEXT,Parent type for inheritance
is_composite,INTEGER DEFAULT 0,1 = container type (e.g. SECTION)
is_required,INTEGER DEFAULT 0,1 = every spec must have at least one
is_default,INTEGER DEFAULT 0,1 = used when header has no explicit type
pid_prefix,TEXT,Default PID prefix for auto-generation
pid_format,TEXT DEFAULT '%s-%03d',Printf format for auto-generated PIDs
aliases,TEXT,"Comma-wrapped aliases (e.g. "",hlr,req,"")"
```

### spec_float_types

Defines types of floats (e.g., FIGURE, TABLE, PLANTUML).

```list-table:tbl-float-types{caption="spec_float_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique type code (e.g. FIGURE)
long_name,TEXT NOT NULL UNIQUE,Human-readable name
description,TEXT,Documentation
caption_format,TEXT,Printf format for captions (e.g. Figure %d)
counter_group,TEXT,Shared numbering group
aliases,TEXT,Comma-wrapped aliases for syntax recognition
needs_external_render,INTEGER DEFAULT 0,1 = requires external tool
```

### spec_relation_types

Defines types of relations between objects (e.g., VERIFIES, TRACES_TO).

```list-table:tbl-relation-types{caption="spec_relation_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique relation type code
long_name,TEXT NOT NULL UNIQUE,Human-readable name
description,TEXT,Documentation
extends,TEXT,Parent relation type for inheritance
source_type_ref,TEXT FK,Constrain source object type (NULL = any)
target_type_ref,TEXT FK,Constrain target object type (NULL = any)
link_selector,TEXT,"Syntax selector (""@"" or ""#"")"
source_attribute,TEXT,Attribute name for inference
```

### spec_view_types

Defines types of views (e.g., TOC, LOF, ABBREV).

```list-table:tbl-view-types{caption="spec_view_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique view type code
long_name,TEXT NOT NULL UNIQUE,Human-readable name
description,TEXT,Documentation
counter_group,TEXT,Float counter group to list
aliases,TEXT,Comma-wrapped aliases
inline_prefix,TEXT,Prefix for inline syntax (e.g. abbrev)
materializer_type,TEXT,"Materialization strategy (toc, lof, abbrev_list, custom)"
view_subtype_ref,TEXT,Parent view type for subtyped views
needs_external_render,INTEGER DEFAULT 0,1 = requires external tool
```

### spec_specification_types

Defines types of specification documents (e.g., SRS, SDD, SVC).

```list-table:tbl-spec-types{caption="spec_specification_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique specification type code
long_name,TEXT NOT NULL UNIQUE,Human-readable name
description,TEXT,Documentation
extends,TEXT,Parent type for inheritance
is_default,INTEGER DEFAULT 0,1 = default when no explicit type
```

### datatype_definitions

Defines primitive datatypes for attributes (STRING, INTEGER, ENUM, etc.).

```list-table:tbl-datatypes{caption="datatype_definitions columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique datatype ID
long_name,TEXT NOT NULL UNIQUE,Human-readable name
type,TEXT NOT NULL,"Primitive category: STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML"
```

The `type` column determines which value column in `spec_attribute_values` stores the data.

### spec_attribute_types

Defines which attributes each object type can have (EAV schema).

```list-table:tbl-attr-types{caption="spec_attribute_types columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique attribute definition ID
owner_type_ref,TEXT NOT NULL FK,Object type that owns this attribute
long_name,TEXT NOT NULL,Attribute name as written in source
datatype_ref,TEXT NOT NULL FK,Data type (FK to datatype_definitions)
min_occurs,INTEGER DEFAULT 0,Minimum occurrences (0 = optional)
max_occurs,INTEGER DEFAULT 1,Maximum occurrences
min_value,REAL,Minimum bound for INTEGER/REAL
max_value,REAL,Maximum bound for INTEGER/REAL
```

Unique constraint: `(owner_type_ref, long_name)` --- each type can define an attribute name only once.

### enum_values

Defines allowed values for ENUM-type datatypes.

```list-table:tbl-enum-values{caption="enum_values columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Unique enum value ID (e.g. STATUS_DRAFT)
datatype_ref,TEXT NOT NULL FK,Parent ENUM datatype
key,TEXT NOT NULL,Value as written in source
sequence,INTEGER DEFAULT 0,Display order
```

### implicit_type_aliases

Maps header titles to object types for implicit type inference (case-insensitive).

```list-table:tbl-type-aliases{caption="implicit_type_aliases columns" header-rows=1}
Column,Type,Description
alias,TEXT PK COLLATE NOCASE,Title text that triggers this type
object_type_id,TEXT NOT NULL FK,Object type to assign
```

### implicit_spec_type_aliases

Maps document titles (H1) to specification types (case-insensitive).

```list-table:tbl-spec-aliases{caption="implicit_spec_type_aliases columns" header-rows=1}
Column,Type,Description
alias,TEXT PK COLLATE NOCASE,Title text that triggers this type
spec_type_id,TEXT NOT NULL FK,Specification type to assign
```

## Core Schema: Content

The content tables store actual specification data. They answer the question: "What does this specification contain?"

**Authoritative source:** `src/db/schema/content.lua`

### specifications

Root-level specification documents. Each `.md` file produces one row.

```list-table:tbl-specifications{caption="specifications columns" header-rows=1}
Column,Type,Description
identifier,TEXT PK,Filename slug (natural key)
root_path,TEXT NOT NULL UNIQUE,Absolute path to root .md file
long_name,TEXT,Document title from H1 header
type_ref,TEXT FK,Specification type
pid,TEXT,Project identifier from @PID syntax
header_ast,JSON,Rendered H1 header as Pandoc AST
body_ast,JSON,Body content between H1 and first H2
```

### spec_objects

Traceable elements within a specification. Created from H2--H6 headers.

```list-table:tbl-objects{caption="spec_objects columns" header-rows=1}
Column,Type,Description
id,INTEGER PK,Auto-assigned internal key
content_sha,TEXT,SHA1 checksum for change detection
specification_ref,TEXT NOT NULL FK,Parent specification
type_ref,TEXT NOT NULL FK,Object type
from_file,TEXT NOT NULL,Source file path
file_seq,INTEGER NOT NULL,Sequence within file (0-indexed)
pid,TEXT,Project identifier
pid_prefix,TEXT,Extracted PID prefix
pid_sequence,INTEGER,Extracted PID sequence number
pid_auto_generated,INTEGER DEFAULT 0,1 = PID was auto-generated
title_text,TEXT NOT NULL,Plain-text title
label,TEXT,Unified label for # resolution
level,INTEGER,Heading level (2--6)
start_line,INTEGER,Start line in source (1-indexed)
end_line,INTEGER,End line in source
ast,JSON,Body as Pandoc AST
content_xhtml,TEXT,Cached HTML5 rendering
```

Key indexes: `idx_objects_spec_label` (UNIQUE on specification_ref + label), `idx_objects_spec_pid` (on specification_ref + pid).

### spec_floats

Numbered floating elements. Created from fenced code blocks with `syntax:label`.

```list-table:tbl-floats{caption="spec_floats columns" header-rows=1}
Column,Type,Description
id,INTEGER PK,Auto-assigned internal key
content_sha,TEXT,SHA1 checksum for change detection
specification_ref,TEXT NOT NULL FK,Parent specification
type_ref,TEXT NOT NULL FK,Float type
from_file,TEXT NOT NULL,Source file path
file_seq,INTEGER NOT NULL,Sequence within file
start_line,INTEGER,Start line in source
label,TEXT NOT NULL,Cross-reference label
number,INTEGER,Auto-assigned number within counter group
caption,TEXT,Caption text
pandoc_attributes,JSON,Parsed attributes from code block
raw_content,TEXT,Original raw content
raw_ast,JSON,Original Pandoc AST
resolved_ast,JSON,Processed AST after rendering
parent_object_id,INTEGER FK,Containing spec object
anchor,TEXT,HTML anchor for linking
syntax_key,TEXT,Original syntax from code block
```

### spec_relations

Traceability links between objects. Created from `[target](@)` and `[target](#)` syntax.

```list-table:tbl-relations{caption="spec_relations columns" header-rows=1}
Column,Type,Description
id,INTEGER PK,Auto-assigned internal key
content_sha,TEXT,SHA1 checksum for change detection
specification_ref,TEXT NOT NULL FK,Parent specification
source_object_id,INTEGER NOT NULL FK,Source object
target_text,TEXT,Target as written (before resolution)
target_object_id,INTEGER FK,Resolved target object (NULL if unresolved)
target_float_id,INTEGER FK,Resolved target float (NULL if unresolved)
type_ref,TEXT FK,Inferred relation type
is_ambiguous,INTEGER DEFAULT 0,1 = multiple matches found
from_file,TEXT NOT NULL,Source file
link_line,INTEGER DEFAULT 0,Line number of link
source_attribute,TEXT,Attribute containing the link (NULL if in body)
link_selector,TEXT,"Selector syntax (""@"" or ""#"")"
```

### spec_views

Dynamic content blocks. Created from inline code with `` `type:param` `` syntax.

```list-table:tbl-views{caption="spec_views columns" header-rows=1}
Column,Type,Description
id,INTEGER PK,Auto-assigned internal key
content_sha,TEXT,SHA1 checksum for change detection
specification_ref,TEXT NOT NULL FK,Parent specification
view_type_ref,TEXT NOT NULL FK,View type
from_file,TEXT NOT NULL,Source file path
file_seq,INTEGER NOT NULL,Sequence within file
start_line,INTEGER,Start line in source
raw_ast,JSON,Original Pandoc AST
resolved_ast,JSON,Materialized view as Pandoc AST
resolved_data,JSON,Pre-computed view data
```

### spec_attribute_values

Typed attribute storage using the Entity-Attribute-Value (EAV) pattern.

```list-table:tbl-attributes{caption="spec_attribute_values columns" header-rows=1}
Column,Type,Description
id,INTEGER PK,Auto-assigned internal key
content_sha,TEXT,SHA1 checksum for change detection
specification_ref,TEXT NOT NULL FK,Parent specification
owner_object_id,INTEGER FK,Owner spec object (NULL if float)
owner_float_id,INTEGER FK,Owner spec float (NULL if object)
name,TEXT NOT NULL,Attribute name
raw_value,TEXT,Original value (before type casting)
string_value,TEXT,For STRING datatype
int_value,INTEGER,For INTEGER datatype
real_value,REAL,For REAL datatype
bool_value,INTEGER,For BOOLEAN datatype (0/1)
date_value,TEXT,For DATE datatype (YYYY-MM-DD)
enum_ref,TEXT FK,For ENUM datatype (FK to enum_values)
ast,JSON,For XHTML datatype (Pandoc AST)
datatype,TEXT NOT NULL,Actual datatype used
xhtml_value,TEXT,Cached HTML5 rendering
```

The EAV pattern is used because the attribute set is unknown at schema creation time --- models define custom attributes at runtime.

## Non-Core Tables

The following tables are **not part of the SpecIR specification**. They are SpecCompiler implementation details for incremental builds, full-text search, and output caching. External tools should ignore these tables.

**Authoritative source:** `src/db/schema/build.lua` and `src/db/schema/search.lua`

### Build Infrastructure

- **build_graph** --- tracks file include/dependency relationships for incremental builds. Columns: `root_path`, `node_path`, `node_sha1`.
- **source_files** --- stores SHA1 hashes of source files for change detection. Columns: `path`, `sha1`.
- **output_cache** --- tracks generated output files and their source state. Columns: `spec_id`, `output_path`, `pir_hash`, `generated_at`.

### Full-Text Search

- **fts_objects** --- FTS5 virtual table indexing spec object text.
- **fts_attributes** --- FTS5 virtual table indexing attribute values.
- **fts_floats** --- FTS5 virtual table indexing float content.

These tables are populated during the EMIT phase and used by the HTML5 web application for browser-native search.

## Views

### EAV Pivot Views

SpecIR dynamically generates per-type views that pivot the EAV table into a columnar format:

```
view_{TYPE}_objects
```

For example, `view_HLR_objects` provides columns like `pid`, `title_text`, `status`, `priority`, `rationale` --- one row per HLR object, with attributes as typed columns instead of EAV rows. These views are generated at runtime after type definitions are loaded.

External tools querying SpecIR should prefer these pivot views over raw EAV joins.

### Public API Views

SpecIR defines stable public views for BI tools and dashboards. These views abstract internal schema complexity and provide stable column names.

**Authoritative source:** `src/db/views/public_api.lua`

- **public_traceability_matrix** --- all resolved object-to-object relations with source/target PIDs, types, and titles.
- **public_coverage_report** --- traceability status of each object (orphan, traces_only, traced_by_only, fully_traced).
- **public_dangling_references** --- unresolved relations (broken links).
- **public_float_inventory** --- all floats with type, caption, number, and parent object.
- **public_object_summary** --- object counts by type.
- **public_specification_list** --- all specifications with object/float/relation counts.

## Interoperability

SpecIR is designed as a hub for specification interchange:

- **CommonSpec** compiles into SpecIR via SpecCompiler.
- **ReqIF** can be exported from SpecIR (current) and imported into SpecIR (planned).
- **SQL** provides direct read/write access for custom tooling, dashboards, and integrations.
- **Any format** that can express typed objects, attributes, and relations can map to and from SpecIR.

The formal separation of the SpecIR schema from the SpecCompiler implementation enables third-party tools to produce and consume SpecIR databases without depending on SpecCompiler.
