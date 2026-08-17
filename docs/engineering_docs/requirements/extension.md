## Extension Requirements

### SF: Extension Framework @SF-005

The extension framework shall let models define types, rendering behavior, data views, verification queries, and output processing.

> description: A model contains descriptor modules and optional format-specific components. The host loads each model without type-specific control flow.

> rationale: Model extensions support domain-specific documents without changes to the core pipeline.

#### HLR: Type Descriptor Loading @HLR-EXT-001

The system shall load type descriptors from model directories.

> description: The host scans these directories under `models/{model}/types/`:
>
> - `objects/` for `kind = "object"`
> - `specifications/` for `kind = "specification"`
> - `floats/` for `kind = "float"`
> - `views/` for `kind = "view"`
> - `relations/` for `kind = "relation"`
>
> Each Lua module returns one descriptor table. The host uses `schema.id` as the type identifier. The file name does not define the identifier.

> rationale: One loading contract gives all type categories the same validation and registration behavior.

> status: Approved

#### HLR: Model Directory Structure @HLR-EXT-002

The system shall use a standard model directory structure.

> description: A model can contain the following paths:
>
> ```text
> models/{model}/
>   model.yaml
>   types/
>     objects/
>     specifications/
>     floats/
>     views/
>     relations/
>   analyze_queries/
>   filters/
>   postprocessors/
>   styles/
>   tools/
> ```
>
> Only the directories required by the model must exist. A type directory can contain a Lua file or a subdirectory with `init.lua`.

> rationale: A standard structure permits deterministic discovery and keeps model-owned components together.

> status: Approved

#### HLR: Descriptor Registration @HLR-EXT-003

Each extension module shall return one descriptor with `kind`, `schema`, and optional `hooks` fields.

> description: The host shall reject an unknown kind, a missing `schema.id`, an invalid hook, and behavior outside `hooks`. The host shall register schema data and index each behavior hook.

> rationale: A uniform descriptor removes category-specific registration interfaces.

> status: Approved

#### HLR: Type Schema @HLR-EXT-004

Each descriptor shall declare the schema fields required by its kind.

> description: The host shall store schema data in the applicable SpecIR type tables. Object and float schemas can declare attribute definitions. A schema can use `extends` to inherit attributes and hooks.

> rationale: Declarative schemas support registration, validation, and inheritance without procedural setup.

> status: Approved

#### HLR: Model Resolution and Overlay @HLR-EXT-005

The system shall resolve and load models as ordered overlays.

> description: The host shall search `$SPECCOMPILER_HOME/models/{model}` first. It shall then search `models/{model}` under the working directory. The host shall load `default` before the selected model. A later descriptor with the same `kind` and `schema.id` shall replace the earlier descriptor. A missing selected or required model shall stop the build.

> rationale: Ordered overlays let a model replace selected definitions and inherit all other default definitions.

> status: Approved

#### HLR: External Renderer Hooks @HLR-EXT-006

An externally rendered float shall declare task preparation and result handling in its descriptor.

> description: The descriptor shall set `schema.needs_external_render = true`. Its `hooks` table shall provide `prepare_task` and `handle_result`. The core shall prepare tasks, apply the render cache, run tasks, and dispatch results. A float shall not declare both `render` and external-render hooks.

> rationale: The hook pair separates type-specific rendering from process scheduling and cache control.

> status: Approved

#### HLR: Data View Hooks @HLR-EXT-007

The system shall obtain generated data from hooks on view descriptors.

> description: A view can declare a `dataset` hook for chart data. A `TABLE_VIEW` subtype shall provide an inherited or local `build_block` hook. The host shall map `inline_prefix` and `aliases` to view identifiers.

> rationale: Data hooks keep query logic in the model that defines the view.

> status: Approved

#### HLR: Hook Index @HLR-EXT-008

The host shall index registered behavior hooks by kind, type identifier, and hook name.

> description: Consumers shall resolve hooks through the host index. Inherited lookup shall follow the `schema.extends` chain. Phase hooks shall use pipeline registration and shall not use the behavior-hook index.

> rationale: One hook index provides deterministic dispatch for all model types.

> status: Approved

#### HLR: Canonical Hook Context @HLR-EXT-009

The host shall pass each behavior hook one frozen context table.

> description: The context shall contain the fields for its tier. The `subject` field shall contain the hook-specific input. The `capability` field shall identify the hook. The `ctx:require(field)` method shall stop execution when a required field is nil.

> rationale: One context argument prevents positional-argument drift and makes required data explicit.

> status: Approved

#### HLR: Model Manifest @HLR-EXT-010

The host shall read model dependencies from `model.yaml`.

> description: The optional `requires` field shall contain model names. The host shall load each required model before the requesting model. It shall load each model at most once. A missing manifest or `requires` field shall define no dependencies.

> rationale: Explicit dependencies produce a deterministic overlay order.

> status: Approved

#### HLR: Hook Validation and Phase Registration @HLR-EXT-011

The host shall validate hooks and register phase participation from the descriptor.

> description: A hook name shall be valid for the descriptor kind. A hook shall return the value type defined by its contract. A phase hook shall use the name `on_<phase>` in `hooks`. The host shall register phase hooks under `<lowercase schema.id>_handler`. The optional `schema.phase_prerequisites` field shall define handler ordering.

> rationale: Load-time and dispatch-time checks detect invalid extensions at their source.

> status: Approved

#### HLR: Analyze Query Descriptor @HLR-EXT-012

The system shall register each analysis query as a `kind = "analyze"` descriptor.

> description: The schema shall contain `id`, `policy_key`, `view`, `sql`, and optional `disabled`. The optional `message` hook shall format a diagnostic for one query row. A later descriptor with the same `policy_key` shall replace the earlier descriptor in place. A descriptor with `disabled = true` shall remove that policy key.

> rationale: Analyze queries use the same descriptor validation and model overlay rules as other extensions.

> status: Approved

#### HLR: Manifest Configuration @HLR-CFG-001

The system shall read build configuration from `project.yaml`.

> description: Environment variables can locate the installed toolchain and support terminal detection. Model behavior and output configuration shall use the frozen project configuration.

> rationale: One configuration source makes builds reproducible.

> status: Approved
