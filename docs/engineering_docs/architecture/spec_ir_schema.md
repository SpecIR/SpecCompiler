## SpecIR Database Schema

### Overview

The Specification [TERM-IR](@) (SpecIR) is implemented as a [TERM-SQLITE](@) schema composed from:

- `src/db/schema/types.lua`
- `src/db/schema/content.lua`
- `src/db/schema/build.lua`
- `src/db/schema/search.lua`
- `src/db/schema/init.lua` (combines all schema modules, initializes EAV pivot views)

The schema has four domains:

```list-table:tbl-SpecIR-domains{caption="Schema domains"}
> header-rows: 1
> aligns: l,l

* - Domain
  - Tables
* - Type system
  - `spec_specification_types`, `spec_object_types`, `spec_float_types`, `spec_relation_types`, `spec_view_types`, `datatype_definitions`, `spec_attribute_types`, `enum_values`
* - Content
  - `specifications`, `spec_objects`, `spec_floats`, `spec_relations`, `spec_views`, `spec_attribute_values`
* - Build cache
  - `build_graph`, `source_files`, `output_cache`
* - Search (FTS5)
  - `fts_objects`, `fts_attributes`, `fts_floats`
```

### Type + Content (SpecIR) @SpecIR

SpecIR is a ReqIF inspired relational metamodel that lowers textual specifications into a typed intermediate representation against which structural validity is evaluated.

Where Pandoc provides the syntactic bridge from Markdown to a structured AST, SpecIR provides the semantic layer by separating: a type layer (Γ), which defines what may exist and a content layer, which records what does exist.

Validation reduces to relational set operations: constraints are expressed as queries over finite sets of entities and relations, and violations emerge as counterexamples (e.g., anti-joins between expected and actual structures).

```plantuml:er-SpecIR-core
@startuml
title SpecIR ER (Core Types + Content)

hide methods
hide stereotypes
skinparam linetype ortho

entity "spec_specification_types" as spec_specification_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  is_default : INTEGER
}

entity "spec_object_types" as spec_object_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  is_composite : INTEGER
  is_required : INTEGER
  is_default : INTEGER
  pid_prefix : TEXT
  pid_format : TEXT
  aliases : TEXT
}

entity "spec_float_types" as spec_float_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  caption_format : TEXT
  counter_group : TEXT
  aliases : TEXT
  needs_external_render : INTEGER
}

entity "spec_relation_types" as spec_relation_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  extends : TEXT
  source_type_ref : TEXT
  target_type_ref : TEXT
  link_selector : TEXT
  source_attribute : TEXT
}

entity "spec_view_types" as spec_view_types {
  * identifier : TEXT
  --
  long_name : TEXT
  description : TEXT
  counter_group : TEXT
  aliases : TEXT
  inline_prefix : TEXT
  materializer_type : TEXT
  view_subtype_ref : TEXT
  needs_external_render : INTEGER
}

entity "datatype_definitions" as datatype_definitions {
  * identifier : TEXT
  --
  long_name : TEXT
  type : TEXT
}

entity "spec_attribute_types" as spec_attribute_types {
  * identifier : TEXT
  --
  owner_type_ref : TEXT
  long_name : TEXT
  datatype_ref : TEXT
  min_occurs : INTEGER
  max_occurs : INTEGER
  min_value : REAL
  max_value : REAL
}

entity "enum_values" as enum_values {
  * identifier : TEXT
  --
  datatype_ref : TEXT
  key : TEXT
  sequence : INTEGER
}

entity "specifications" as specifications {
  * identifier : TEXT
  --
  root_path : TEXT
  long_name : TEXT
  type_ref : TEXT
  pid : TEXT
  header_ast : JSON
  body_ast : JSON
}

entity "spec_objects" as spec_objects {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  pid : TEXT
  pid_prefix : TEXT
  pid_sequence : INTEGER
  pid_auto_generated : INTEGER
  title_text : TEXT
  label : TEXT
  level : INTEGER
  start_line : INTEGER
  end_line : INTEGER
  ast : JSON
  content_xhtml : TEXT
}

entity "spec_floats" as spec_floats {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  start_line : INTEGER
  label : TEXT
  number : INTEGER
  caption : TEXT
  pandoc_attributes : JSON
  raw_content : TEXT
  raw_ast : JSON
  resolved_ast : JSON
  parent_object_id : INTEGER
  anchor : TEXT
  syntax_key : TEXT
}

entity "spec_relations" as spec_relations {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  source_object_id : INTEGER
  target_text : TEXT
  target_object_id : INTEGER
  target_float_id : INTEGER
  type_ref : TEXT
  is_ambiguous : INTEGER
  from_file : TEXT
  link_line : INTEGER
  source_attribute : TEXT
  link_selector : TEXT
}

entity "spec_views" as spec_views {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  view_type_ref : TEXT
  from_file : TEXT
  file_seq : INTEGER
  start_line : INTEGER
  raw_ast : JSON
  resolved_ast : JSON
  resolved_data : JSON
}

entity "spec_attribute_values" as spec_attribute_values {
  * id : INTEGER
  --
  content_sha : TEXT
  specification_ref : TEXT
  owner_object_id : INTEGER
  owner_float_id : INTEGER
  name : TEXT
  raw_value : TEXT
  string_value : TEXT
  int_value : INTEGER
  real_value : REAL
  bool_value : INTEGER
  date_value : TEXT
  enum_ref : TEXT
  ast : JSON
  datatype : TEXT
  xhtml_value : TEXT
}


specifications }o--|| spec_specification_types : type_ref
spec_objects }o--|| specifications : specification_ref
spec_objects }o--|| spec_object_types : type_ref
spec_floats }o--|| specifications : specification_ref
spec_floats }o--|| spec_float_types : type_ref
spec_floats }o--o| spec_objects : parent_object_id
spec_relations }o--|| specifications : specification_ref
spec_relations }o--|| spec_objects : source_object_id
spec_relations }o--o| spec_objects : target_object_id
spec_relations }o--o| spec_floats : target_float_id
spec_relations }o--o| spec_relation_types : type_ref
spec_views }o--|| specifications : specification_ref
spec_views }o--|| spec_view_types : view_type_ref
spec_attribute_values }o--|| specifications : specification_ref
spec_attribute_values }o--o| spec_objects : owner_object_id
spec_attribute_values }o--o| spec_floats : owner_float_id
spec_attribute_values }o--o| enum_values : enum_ref
spec_attribute_types }o--|| spec_object_types : owner_type_ref
spec_attribute_types }o--|| datatype_definitions : datatype_ref
enum_values }o--|| datatype_definitions : datatype_ref
spec_relation_types }o--o| spec_object_types : source_type_ref
spec_relation_types }o--o| spec_object_types : target_type_ref

@enduml
```
