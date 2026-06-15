## Type Discovery Design

### FD: Type Model Discovery and Registration @FD-002

> traceability: [SF-005](@)

**Allocation:** Realized by [CSC-001](@) (Core Runtime) through [CSU-008](@) (Type Loader). The foundational type definitions are provided by [CSC-017](@) (Default Model), which all domain models extend.

The type model discovery function loads model definitions from the filesystem and
registers them with the [dic:pipeline](#) and data manager through ONE uniform
descriptor contract. It enables domain-specific extensibility by allowing models to
define custom specification types, object types, float types, relation types, view
types, verification views, and pipeline handlers.

**Model Overlay**: The host engine ([CSU-008](@)) loads the `default` model first, then
each requested overlay model in turn, later-wins-by-id, so a model overrides only the
type ids it redefines. Models are resolved repo-bundled under
`SPECCOMPILER_HOME/models/{model}` (then cwd); there is no out-of-tree search path,
registry, or package manager, and a requested model with no directory is a loud error.

**Directory Scanning**: The loader scans `models/{model}/types/` for category directories
matching the five type categories:

```list-table:tbl-type-categories{caption="Type category directory mapping"}
> header-rows: 1
> aligns: l,l,l,l

* - Category
  - Directory
  - Descriptor `kind`
  - Database Table
* - Specifications
  - `specifications/`
  - `specification`
  - `spec_specification_types`
* - Objects
  - `objects/`
  - `object`
  - `spec_object_types`
* - Floats
  - `floats/`
  - `float`
  - `spec_float_types`
* - Relations
  - `relations/`
  - `relation`
  - `spec_relation_types`
* - Views
  - `views/`
  - `view`
  - `spec_view_types`
```

A typical model directory layout for the default model:

```
models/default/types/
├── specifications/
│   └── srs.lua        -- returns a specification descriptor
├── objects/
│   ├── hlr.lua        -- returns an object descriptor (hooks = {} -- pure data)
│   └── section.lua    -- returns an object descriptor
├── floats/
│   ├── figure.lua     -- returns a float descriptor (transform data hook)
│   └── plantuml.lua   -- returns a float descriptor (prepare_task/handle_result)
├── relations/
│   └── traces_to.lua  -- returns a relation descriptor
└── views/
    └── toc.lua        -- returns a view descriptor (render_block hook)
```

**Descriptor Loading**: Each `.lua` file returns ONE descriptor table
`{ kind, schema, [hooks] }`. The host validates it -- `kind` is a known
category, `schema.id` is present (and authoritative; the filename is irrelevant),
each declared hook is valid for the kind, and no behaviour is smuggled onto a top-level
key -- then emits the type row into the table for that `kind` and eager-indexes each hook
into the `(kind, id) -> hook` map. A malformed descriptor (unknown kind, missing id,
invalid-for-kind hook, internal-render-plus-external-hooks) is a loud register-time error;
a missing required hook (e.g. a TABLE_VIEW subtype with no `build_block`) is caught at
`host:finalize()`.

**Attribute Registration**: Object and float schemas may declare `attributes` describing
their data schema. The host registers these with the data manager, creating datatype
definitions and attribute constraints (name, type, min/max occurs, enum values, bounds) in
the `spec_attribute_defs` and `spec_datatype_defs` tables; `extends` inherits a base type's
attributes.

**Hooks (two tiers)**: A descriptor declares behaviour only under `hooks`, keyed by name,
and each hook takes ONE frozen context as its sole argument. Per-call RENDER hooks
(`render`, `render_block`, `render_link`, `message`) receive the render context during the
EMIT walk (it carries pandoc/format and the Pandoc element as `subject`). DATA hooks
(`dataset`, `build_block`, `transform`, `resolve`, `prepare_task`, `handle_result`) receive a
data context during the TRANSFORM/ANALYZE/external-render phases. The hook NAME selects the
tier and the return type, and the host validates the mapping. `on_<phase>` functions in `hooks`
contributes an `on_<phase>` hook to the pipeline's order via [dic:prerequisites](#) and
[dic:topological-sort](#); a handler with no `prerequisites` is defaulted to an empty list by
`pipeline:register_handler`.

**Base Types and Inheritance**: A type inherits hooks and attributes from the ancestor named
in `schema.extends`. Every consumer resolves a hook with `get_hook_inherited`, which walks the
`extends` chain, so a shared render lives ONCE on a base type (the object card on `TRACEABLE`,
the spec title on `SPEC_TITLE`, the matrix `render_block` on `TABLE_VIEW`) and leaf types stay
pure schema. A relation's `resolve` data hook IS the type's resolver: the host registers it
through an adapter ([src/contract/registry.lua](../../../src/contract/registry.lua)) so the
ANALYZE-phase relation analyzer dispatches resolution by type id; a concrete relation type
inherits a base resolver via `extends`.

**Custom Display Text**: A relation type that needs custom link text declares a `render_link`
render hook -- `render_link(ctx) -> string|nil` reading `ctx.subject.target`. The
`relation_link_rewriter` (TRANSFORM phase) resolves it via `get_hook_inherited`; returning
`nil` falls through to the base type. The base types `LABEL_REF` and `PID_REF` ship defaults
(title for `SECTION` targets, PID for other objects, `"<caption> <number>"` for floats) that
concrete types inherit automatically.

**Component Interaction**

The type discovery function is realized by the host engine and the default model
that provides foundational type definitions.

[csc:core-runtime](#) (Core Runtime) provides [csu:type-loader](#) (the host engine), which
drives the entire model discovery lifecycle — overlaying `default` then each model
(later-wins-by-id), scanning category directories, loading each module's descriptor,
validating it, registering the type with the data manager, indexing its hooks into the
`(kind, id) -> hook` map, and at `finalize()` propagating inherited attributes, creating
the verification SQL views, and asserting required hooks.

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
        TL -> TL: require(module_path) -> descriptor
        TL -> TL: validate {kind, schema.id, hooks}

        alt kind == "relation"
            TL -> DB: register_relation_type(schema)
            TL -> DB: register_resolver(id, resolve adapter)
        else kind == "float"
            TL -> DB: register_float_type(schema)
        else kind == "object"
            TL -> DB: register_object_type(schema)
            alt has implicit_aliases
                TL -> DB: register_implicit_aliases()
            end
        else kind == "view"
            TL -> DB: register_view_type(schema)
        else kind == "specification"
            TL -> DB: register_specification_type(schema)
            alt has implicit_aliases
                TL -> DB: register_implicit_spec_aliases()
            end
        end

        TL -> TL: index hooks into (kind,id)->hook

        alt has attributes
            TL -> DB: register_attributes(schema.attributes)
        end

        alt hooks contain on_<phase>
            TL -> P: register_handler(derived from on_<phase> hooks)
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

#### LLR: Declared Hooks Are Indexed @LLR-EXT-021-01

A descriptor's declared `hooks` shall be eager-indexed into the host's
`(kind, id) -> hook` map; `on_<phase>` hooks shall be forwarded to
`pipeline:register_handler`, propagating registration errors.

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
> - `extends` field enables single-inheritance (e.g., HLR extends TRACEABLE) with automatic attribute + hook propagation
> - One descriptor table per file (`{kind, schema, hooks}`) co-locates the type definition with its declarative behaviour
> - `require()` loading reuses Pandoc's built-in Lua module system without additional dependency
> - Layered model loading (default first, then domain model) with ID-based override enables extension without forking the default model
> - Alternative of YAML/JSON config rejected: no computed defaults, no handler co-location
