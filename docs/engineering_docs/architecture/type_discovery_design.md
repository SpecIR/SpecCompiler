## Type Discovery Design

### FD: Type Model Discovery and Registration @FD-002

> traceability: [SF-005](@)

**Allocation:** Realized by [CSC-001](@) (Core Runtime) through [CSU-008](@) (Type Loader). The foundational type definitions are provided by [CSC-017](@) (Default Model), which all domain models extend.

The type model discovery function loads model definitions from the filesystem and
registers them with the [dic:pipeline](#) and data manager. It enables domain-specific
extensibility by allowing models to define custom specification types, object types,
float types, relation types, view types, and pipeline handlers.

**Model Path Resolution**: The [dic:type-loader](#) ([CSU-008](@)) resolves the model directory by
checking `SPECCOMPILER_HOME/models/{model}` first, then falling back to the project root.
This two-stage resolution allows global model installation while supporting project-local overrides.

**Directory Scanning**: The loader scans `models/{model}/types/` for category directories
matching the five type categories:

```list-table:tbl-type-categories{caption="Type category directory mapping"}
> header-rows: 1
> aligns: l,l,l,l

* - Category
  - Directory
  - Export Field
  - Database Table
* - Specifications
  - `specifications/`
  - `M.specification`
  - `spec_specification_types`
* - Objects
  - `objects/`
  - `M.object`
  - `spec_object_types`
* - Floats
  - `floats/`
  - `M.float`
  - `spec_float_types`
* - Relations
  - `relations/`
  - `M.relation`
  - `spec_relation_types`
* - Views
  - `views/`
  - `M.view`
  - `spec_view_types`
```

A typical model directory layout for the default model:

```
models/default/types/
├── specifications/
│   └── srs.lua        -- exports M.specification
├── objects/
│   ├── hlr.lua        -- exports M.object
│   └── section.lua    -- exports M.object
├── floats/
│   ├── figure.lua     -- exports M.float
│   └── plantuml.lua   -- exports M.float + M.handler
├── relations/
│   └── traces_to.lua  -- exports M.relation
└── views/
    └── toc.lua        -- exports M.view
```

**Module Loading**: Each `.lua` file in a category directory is loaded via `require()`.
The loader inspects the module's export fields to determine the type category and calls
the appropriate registration method on the data manager. If a
module exports `M.handler`, the handler is also registered with the pipeline for
phase-specific processing.

**Attribute Registration**: Object and float types may declare `attributes` tables
describing their data schema. The loader registers these with the data manager, creating
datatype definitions and attribute constraints (name, datatype, min/max occurs, enum
values, bounds) in the `spec_attribute_defs` and `spec_datatype_defs` tables.

**Handler Registration**: Type modules may export a `M.handler` table with phase hooks.
These handlers extend the pipeline's processing
capabilities with type-specific logic (e.g., PlantUML float rendering, traceability matrix
view materialization). Handlers declare [dic:prerequisites](#) to control execution ordering via
[dic:topological-sort](#).

**Base Types**: Relation type modules may export `M.base` instead of `M.relation` to act as
base types that own resolution logic. Base types are not registered in the database. The type
loader registers their `M.resolve` function into `_selector_resolvers` (keyed by
`M.base.link_selector`), which the relation resolver dispatches to during the ANALYZE phase.
Concrete relation types use `M.extend(overrides)` to inherit base properties (e.g.,
`link_selector`) while adding their own constraints. This follows the same delegation pattern
as float type modules (`src/pipeline/transform/spec_floats.lua`).

**Custom Display Text**: Relation types that need custom link display text (e.g., showing
title instead of PID) export a standard `M.handler` with `on_transform` using the shared
`link_rewrite_utils.rewrite_display_for_type()` utility.

**Component Interaction**

The type discovery function is realized by the core type loader and the default model
that provides foundational type definitions.

[csc:core-runtime](#) (Core Runtime) provides [csu:type-loader](#) (Type Loader), which drives the entire
model discovery lifecycle — resolving model paths, scanning category directories, loading
modules via `require()`, registering types and handlers with the data manager and pipeline,
and propagating inherited attributes and relation properties.

[csc:default-model](#) (Default Model) provides the two foundational types that every domain model
inherits. [csu:section-object-type](#) (SECTION Object Type) defines the implicit structural type for
untitled content sections, enabling document structure representation without requiring
explicit type declarations. [csu:spec-specification-type](#) (SPEC Specification Type) defines the base
specification type with version, status, and date attributes that all domain-specific
specification types extend.

```puml:fd-002-type-discovery{caption="Type Model Discovery and Registration"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "CSU Build Engine" as E
participant "CSU Type Loader" as TL
participant "Filesystem" as FS
participant "CSU Data Manager" as DB
participant "CSU Pipeline" as P

E -> TL: load_model(data, pipeline, "default")
activate TL

TL -> TL: resolve_model_path()
note right: Check SPECCOMPILER_HOME\nthen project root

TL -> FS: scan models/{model}/types/
FS --> TL: category directories

loop for each category
    TL -> FS: list *.lua files
    FS --> TL: module paths

    loop for each module
        TL -> TL: require(module_path)

        alt has M.relation AND M.resolve
            TL -> TL: _selector_resolvers[selector] = M.resolve
            TL -> DB: register_relation_type(M.relation)
        else has M.float
            TL -> DB: register_float_type(M.float)
        else has M.relation
            TL -> DB: register_relation_type(M.relation)
        else has M.object
            TL -> DB: register_object_type(M.object)
            alt has implicit_aliases
                TL -> DB: register_implicit_aliases()
            end
        else has M.view
            TL -> DB: register_view_type(M.view)
        else has M.specification
            TL -> DB: register_specification_type(M.specification)
            alt has implicit_aliases
                TL -> DB: register_implicit_spec_aliases()
            end
        end

        alt has attributes
            TL -> DB: register_attributes(attributes)
        end

        alt has M.handler
            TL -> P: register_handler(M.handler)
        end
    end
end

TL -> DB: propagate_inherited_attributes()
note right: Copy parent attributes\nto child types (iterative)

TL --> E: types and handlers registered
deactivate TL
@enduml
```

#### LLR: Known Type Categories Are Scanned @LLR-EXT-020-01

Type loading shall scan each known category directory
(`objects`, `floats`, `views`, `relations`, `specifications`) and register
discovered modules.

> verification_method: Test

> traceability: [HLR-EXT-002](@)

#### LLR: Exported Handlers Are Registered @LLR-EXT-021-01

When a type module exports `handler`, model loading shall call
`pipeline:register_handler(handler)` and propagate registration errors.

> verification_method: Test

> traceability: [HLR-EXT-003](@)

#### LLR: Handler attr_order Controls Attribute Display Sequence @LLR-EXT-021-02

When a type handler is created with an `attr_order` array in its options,
the handler shall render attributes in the specified sequence first; any remaining
attributes not listed in `attr_order` shall be appended alphabetically. When `attr_order`
is absent, all attributes shall render alphabetically.

> verification_method: Test

> traceability: [HLR-EXT-003](@)

#### LLR: Schemas Without Identifier Are Ignored @LLR-EXT-022-01

Category registration helpers shall ignore schema tables that do
not provide `id`; valid schemas shall receive category defaults and attribute
enum values shall be registered.

> verification_method: Test

> traceability: [HLR-EXT-004](@)

#### LLR: Model Path Resolution Order @LLR-EXT-023-01

Model path resolution shall check `SPECCOMPILER_HOME/models/{model}`
before checking `{cwd}/models/{model}`.

> verification_method: Test

> traceability: [HLR-EXT-005](@)

#### LLR: Missing Model Paths Fail Fast @LLR-EXT-023-02

Model loading shall raise an error when the model cannot be
located in either `SPECCOMPILER_HOME` or project-root `models/`.

> verification_method: Test

> traceability: [HLR-EXT-005](@)

#### LLR: Data Views Resolve With Default Fallback @LLR-EXT-024-01

Chart data view loading shall resolve
`models.{requested}.types.views.{view}` first and fallback to
`models.default.types.views.{view}` when the requested model module is missing.

> verification_method: Test

> traceability: [HLR-EXT-006](@)

#### LLR: Sankey Views Inject Series Data And Clear Dataset @LLR-EXT-024-02

When a chart contains a `sankey` series and view output returns
`data`/`links`, injection shall write to `series[1].data` and
`series[1].links`, and clear `dataset` to prevent conflicts.

> verification_method: Test

> traceability: [HLR-EXT-006](@)

#### LLR: Chart Injection Leaves Config Intact For No-View Or Unsupported View Data @LLR-EXT-024-03

Chart data injection shall preserve input chart configuration when
no `view` is provided or when view output does not match supported shapes
(`source` or `data`+`links` for sankey).

> verification_method: Test

> traceability: [HLR-EXT-006](@)

#### LLR: Type Handler Render Registration @LLR-094

Given a [dic:type](#) module with `handler` export, [csu:type-loader](#) shall call
`pipeline:register_handler(handler)` to activate render callbacks for that type.

> verification_method: Test

> traceability: [HLR-EXT-001](@)

#### LLR: Data View Generator Discovery @LLR-095

Given a [dic:model](#) name, [csu:type-loader](#) shall scan the
`models/{model}/types/views/` directory and register discovered [dic:data-view](#)
modules.

> verification_method: Test

> traceability: [HLR-EXT-007](@)

#### LLR: Handler Module Caching @LLR-096

When a module path is requested, [csu:type-loader](#) shall return the cached module if
previously loaded; on first load, it shall store the result in a per-path cache.

> verification_method: Test

> traceability: [HLR-EXT-008](@)

---

### DD: Lua-Based Type System with Inheritance @DD-CORE-006

Selected Lua modules with `extends` chains for type definitions.

> rationale: Lua modules as type definitions enable:
>
> - Type definitions are executable code, supporting computed defaults and complex attribute constraints
> - `extends` field enables single-inheritance (e.g., HLR extends TRACEABLE) with automatic attribute propagation
> - Module exports (M.object, M.float, M.handler) co-locate type definition with optional handler registration
> - `require()` loading reuses Pandoc's built-in Lua module system without additional dependency
> - Layered model loading (default first, then domain model) with ID-based override enables extension without forking the default model
> - Alternative of YAML/JSON config rejected: no computed defaults, no handler co-location
