## Type System Architecture @type

### Overview

SpecCompiler uses a dynamic type system where models define available types for objects, [TERM-04](@), relations, and views.

```plantuml:comp-types{caption="Type System Architecture (COMP-002)"}
@startuml
skinparam componentStyle rectangle
skinparam defaultTextAlignment center

package "models/{model}/types/" as model {
  [specifications/] as specs
  [objects/] as objs
  [floats/] as floats
  [relations/] as rels
  [views/] as views
}

component "TypeLoader" as TL

database "SpecIR (SQLite)" as DB {
  [spec_specification_types] as t_spec
  [spec_object_types] as t_obj
  [spec_float_types] as t_float
  [spec_relation_types] as t_rel
  [spec_view_types] as t_view
}

component "Pipeline" as PL

specs --> TL
objs --> TL
floats --> TL
rels --> TL
views --> TL

TL --> t_spec : register
TL --> t_obj : register
TL --> t_float : register
TL --> t_rel : register
TL --> t_view : register

TL --> PL : handlers

@enduml
```

### Type Module Structure

Each type module exports a category-specific definition:

```lua
-- Example: models/default/types/objects/hlr.lua
local M = {}

M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    description = "System-level requirement",
    extends = "TEXTUAL",
    attributes = {
        { name = "status", datatype = "STATUS_ENUM", min_occurs = 1 },
        { name = "rationale", datatype = "STRING" }
    }
}

-- Optional handler for custom rendering
M.handler = {
    name = "hlr_render",
    prerequisites = { "spec_objects" },
    on_transform = function(data, ctx, diag) ... end
}

return M
```

### Type Categories

| Category | Database Table | Key Fields |
|----------|---------------|------------|
| Specifications | spec_specification_types | id, long_name, extends, is_default |
| Objects | spec_object_types | id, long_name, extends, is_default (HLR, FD, CSC, CSU, VC, etc.) |
| Floats | spec_float_types | id, long_name, counter_group, needs_external_render |
| Relations | spec_relation_types | id, source_type_ref, target_type_ref, link_selector |
| Views | spec_view_types | id, materializer_type, counter_group |

### Loading Process

1. [TERM-38](@) scans models/{model}/types/{category}/
2. Each .lua file is loaded and checked for exports
3. Type definitions registered in corresponding DB tables
4. Handlers registered with pipeline if present
