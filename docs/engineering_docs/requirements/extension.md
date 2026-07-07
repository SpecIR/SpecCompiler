## Extension Requirements

### SF: Extension Framework @SF-005

Model-based extensibility for type [dic:handler](#), renderers, and [dic:data-view](#).

> description: Groups requirements for the extension mechanism that enables custom models
> to provide type handlers, [dic:external-renderer](#), data view generators, and style presets.

> rationale: Extensibility through model directories enables domain-specific customization
> without modifying the core pipeline.

### Host Engine + Descriptor Plugins (Refactor Deltas)

The extension framework was unified onto **one declarative contract**: a model-agnostic
**Host Engine** (`src/contract/registry.lua`) that loads **Descriptor Plugins**. The four
former registration mechanisms (type loader if/elseif dispatch, the external-renderer
require-time registry, the verification-view loader, the data-view loader) and the four
`{model}:{type_ref}` handler caches are collapsed into one host with a single eager
`(kind, id) -> hook` index.

**The descriptor is the contract.** Every extension point is one module that declares:

```lua
{
  kind   = "object|float|view|relation|specification|verification|dataview",
  schema = { id = "HLR", long_name = ..., extends = "TRACEABLE", attributes = {...},
             -- kind-specific: inline_prefix/aliases (view);
             --   caption_format/needs_external_render (float); link_selector/source_type_ref/
             --   target_type_ref (relation); view/policy_key/sql/disabled (verification) },
  hooks  = { render=, render_link=, resolve=, generate=, prepare_task=,
             handle_result=, message=, on_<phase>= },  -- absent hook => host default
}
```

The host introspects only the declared `hooks`; **role is inferred from which hooks are
present** (a relation with `resolve` is a resolver; a float with `prepare_task`/`handle_result`
renders externally and may NOT also declare `render`). Type `id` is read from
`schema.id` (the filename is discovery sugar, never the identity), and a missing `schema.id`
or an unknown kind is a LOUD register-time error. The host runs once per build:
`host:load_model(default)` then each overlay model (later-wins-by-id), then `finalize()`
(attribute inheritance + verification SQL views).

**Requirement deltas:**

| ID | Status | Delta |
|---|---|---|
| HLR-EXT-001 | Changed | Type `id` comes from descriptor `schema.id`; the filename is irrelevant; categories are discovery sugar, not lowercased identity. |
| HLR-EXT-002 | Kept | Frozen in-tree model layout (see also HLR-EXT-010 `model.yaml`). |
| HLR-EXT-003 | Changed | A plugin returns one descriptor `{kind, schema, hooks}`; the host introspects declared `hooks` instead of five divergent `M.handler` interfaces. |
| HLR-EXT-004 | Changed | One declarative `schema` per kind (the IR columns that kind needs); inheritance via `extends`. |
| HLR-EXT-005 | **Retired** | The per-type model→default `require` fallback is gone; the host overlay (default then template, later-wins-by-id) replaces it. A fully-absent requested model is a loud error. |
| HLR-EXT-006 | Changed | External rendering is `prepare_task`/`handle_result` **hooks** indexed by the host, not a require-time `external_render.register_renderer` side effect. |
| HLR-EXT-007 | Changed | Data-view generation is a `generate` **hook** the host indexes; `data_loader` retains only the chart-config injection + a loose-load fallback for unregistered/fixture generators. |
| HLR-EXT-008 | **Retired** | The `{model}:{type_ref}` handler caches (incl. the `= false` negative cache) are deleted; the eager `(kind,id)->hook` index replaces them. A nil index ("not registered") is a distinct loud state from "registered, no such hook". |

**New requirement stubs:**

#### HLR: Canonical Context @HLR-EXT-009

The host shall pass every plugin hook a single frozen canonical `ctx` whose invariant core
(`data, pandoc, log, diagnostics, format, spec_id, model, config`) is guaranteed non-nil
and asserted at build time; only `subject` is polymorphic (shape documented per kind).
`ctx:require(field)` fails loudly on nil. (`src/contract/ctx.lua`.)

> status: Approved

#### HLR: Model Manifest @HLR-EXT-010

Each in-tree model shall carry a `model.yaml` (`name`, `description`, `extends`, `requires`)
that declares the overlay chain. Models stay repo-bundled under `models/<name>/`; there is no
out-of-tree search path, registry, or package manager. (A symlinked model is not Docker-safe
and must be vendored in-tree to ship.)

> status: Approved

#### HLR: Descriptor + Role Inference @HLR-EXT-011

A plugin shall return one descriptor `{kind, schema, hooks}`. The host classifies each
`hooks` field by name (per-item hooks dispatched inline; `on_<phase>` hooks synthesized into
`pipeline:register_handler`), infers role from the hooks present, and validates an optional
`schema.role` echo against them. Malformed descriptors (unknown kind, missing `schema.id`,
hook invalid for the kind, internal-render-plus-external-hooks) are loud register-time errors.

> status: Approved

#### HLR: Verification Descriptor @HLR-EXT-012

A analyze query shall be a `kind="verification"` descriptor
(`schema = {policy_key, view, sql, disabled}`, `hooks = {message}`) forwarded to the host's
ordered policy_key registry, preserving override (later model wins, in place) and
`disabled=true` removal semantics. (Closes the HLR-TYPE-007 contract gap.)

> status: Approved

#### HLR: Manifest-Only Configuration @HLR-CFG-001

All build configuration shall come from `project.yaml`, read once into a frozen `config`
slice. `os.getenv` is permitted ONLY to bootstrap the toolchain (`SPECCOMPILER_HOME`,
`SPECCOMPILER_DIST`) and for terminal autodetect (`TERM`, `CI`, `NO_COLOR`,
`NUMBER_OF_PROCESSORS`). The former config-leak env reads (`OUTPUT_FORMAT`, `BUILD_DIR`,
`SPECCOMPILER_LOG_LEVEL`) are removed; the manifest is authoritative.

> status: Approved

#### HLR: Model-Specific Type Handler Loading @HLR-EXT-001

The system shall load type-specific handlers from model directories.

> description: Type handlers control how specification content is rendered during the [dic:transform-phase](#) phase. The loading mechanism supports:
>
> - **Object types**: Loaded from `models/{model}/types/objects/{type}.lua`
> - **Specification types**: Loaded from `models/{model}/types/specifications/{type}.lua`
> - **Float types**: Loaded from `models/{model}/types/floats/{type}.lua`
> - **View types**: Loaded from `models/{model}/types/views/{type}.lua`
>
> Module loading uses `require()` with path `models.{model}.types.{category}.{type}`. Type names are converted to lowercase for file lookup (e.g., "HLR" -> "hlr.lua").

> rationale: Separating type handlers into model directories enables domain-specific customization. Organizations can define their own requirement types, document types, and rendering behavior without modifying core code.

> status: Approved


#### HLR: Model Directory Structure @HLR-EXT-002

The system shall organize model content in a standardized directory hierarchy.

> description: Each model follows this structure:
>
> ```
> models/{model_name}/
>   types/
>     objects/       -- Spec object type handlers (HLR, LLR, VC, etc.)
>     specifications/-- Specification type handlers (SRS, SDD, SVC)
>     floats/        -- Float type handlers (TABLE, PLANTUML, CHART)
>     views/         -- View type handlers (ABBREV, SYMBOL, MATH)
>     relations/     -- Relation type definitions (TRACES_TO, etc.)
>   analyze_queries/ -- Verification descriptors (SQL views + message hooks)
>   filters/         -- Pandoc filters (docx.lua, html.lua, markdown.lua)
>   postprocessors/  -- Format-specific postprocessors
>   styles/          -- Style presets and templates
> ```
>
> Model names are referenced via project configuration `template` field or context `model_name`. The "default" model provides base implementations with fallback behavior.

> rationale: Standardized structure enables consistent discovery of type modules across models and provides clear extension points for each content category.

> status: Approved


#### HLR: Handler Registration Interface @HLR-EXT-003

Type handlers shall provide standardized registration interfaces for pipeline integration.

> description: Each handler category defines specific interfaces:
>
> **Object Type Handlers** export:
> - `M.object`: Type schema with id, long_name, description, attributes
> - `M.handler.on_render_SpecObject(obj, ctx)`: Render function returning Pandoc blocks
>
> **Specification Type Handlers** export:
> - `M.specification`: Type schema with id, long_name, attributes
> - `M.handler.on_render_Specification(ctx, pandoc, data)`: Render document title
>
> **Float Type Handlers** export:
> - `M.float`: Type schema with id, caption_format, counter_group, aliases, needs_external_render
> - `M.transform(raw_content, type_ref, log)`: For internal transforms (TABLE, CSV)
> - `external_render.register_renderer(type_ref, callbacks)`: For external renders (PLANTUML, CHART)
>
> **View Type Handlers** export:
> - `M.view`: Type schema with id, inline_prefix, aliases
> - `M.handler.on_render_Code(code, ctx)`: Inline code rendering

> rationale: Consistent interfaces enable the core pipeline to discover and invoke handlers without knowledge of specific type implementations. This separation maintains extensibility.

> status: Approved


#### HLR: Type Definition Schema @HLR-EXT-004

Type definitions shall declare metadata schema that controls registration and behavior.

> description: Type schemas provide metadata stored in registry tables:
>
> **Object Types** (`spec_object_types`):
> ```lua
> M.object = {
>     id = "HLR",                    -- Unique identifier (uppercase)
>     long_name = "High-Level Requirement",
>     description = "A top-level system requirement",
>     extends = "TRACEABLE",         -- Base type for inheritance
>     header_unnumbered = true,      -- Exclude from section numbering
>     header_style_id = "Heading2",  -- Custom-style for headers
>     body_style_id = "Normal",      -- Custom-style for body
>     attributes = {                 -- Attribute definitions
>         { name = "status", type = "ENUM", values = {...}, min_occurs = 1 },
>         { name = "rationale", type = "XHTML" },
>         { name = "created", type = "DATE" },
>     }
> }
> ```
>
> **Float Types** (`spec_float_types`):
> ```lua
> M.float = {
>     id = "CHART",
>     caption_format = "Figure",     -- Caption prefix
>     counter_group = "FIGURE",      -- Counter sharing (FIGURE, CHART, PLANTUML)
>     aliases = { "echarts" },       -- Alternative syntax identifiers
>     needs_external_render = true,  -- Requires external tool
> }
> ```
>
> **View Types** (`spec_view_types`):
> ```lua
> M.view = {
>     id = "ABBREV",
>     inline_prefix = "abbrev",      -- Syntax: `abbrev: content`
>     aliases = { "sigla", "acronym" },
>     needs_external_render = false,
> }
> ```

> rationale: Declarative schemas enable automatic registration into database tables during initialization, provide validation rules for content, and configure rendering behavior without procedural code.

> status: Approved


#### HLR: Model Path Resolution @HLR-EXT-005

The system shall resolve model paths using environment configuration with fallback.

> description: Model path resolution follows this order:
>
> 1. Check `SPECCOMPILER_HOME` environment variable: `$SPECCOMPILER_HOME/models/{model}`
> 2. Fall back to current working directory: `./models/{model}`
>
> For type modules not found in the specified model, the system falls back to the "default" model:
>
> ```lua
> -- Try model-specific path first
> local module = require("models." .. model_name .. ".types.floats.table")
> -- Fallback to default model
> local module = require("models.default.types.floats.table")
> ```
>
> This enables partial model customization where models only override specific types.

> rationale: Environment-based configuration supports deployment flexibility. Fallback to default model reduces duplication by allowing models to inherit base implementations.

> status: Retired

_Retired in the Host Engine Refactor: the per-type require fallback is replaced by the host overlay; `SPECCOMPILER_HOME`-then-cwd resolution is kept, and a fully-absent model is a loud error._


#### HLR: External Renderer Registration @HLR-EXT-006

External renderers shall declare task-preparation and result-handling hooks on their float descriptor.

> description: Float types requiring external tools (PlantUML, ECharts, etc.) declare the hook pair in their descriptor; the host indexes them like every other hook (no separate registration call):
>
> ```lua
> -- models/{model}/types/floats/plantuml.lua
> return {
>     kind = "float",
>     schema = { id = "PLANTUML", needs_external_render = true, --[[ ... ]] },
>     hooks = {
>         prepare_task = function(ctx)
>             -- Return task descriptor with cmd, args, output_path, context
>         end,
>         handle_result = function(ctx)
>             -- Update resolved_ast in database
>         end,
>     },
> }
> ```
>
> The core orchestrates: query items -> prepare tasks -> cache filter -> batch spawn -> dispatch results. This enables parallel execution across all external renders. A float declares either a `render` hook or the external pair — never both (validated at register time).

> rationale: The descriptor hook pair decouples type-specific rendering logic from core orchestration. Hooks enable types to control task preparation and result interpretation while core handles parallelization and caching.

> status: Approved


#### HLR: Data View Generator Loading @HLR-EXT-007

The system shall provide chart data through `dataset` hooks on view descriptors.

> description: A data view is a view descriptor (`models/{model}/types/views/{view_name}.lua`) that declares a `dataset` data hook returning `{ source = ... }` for the chart consumer:
>
> ```lua
> -- models/{model}/types/views/gaussian.lua
> return {
>     kind = "view",
>     schema = { id = "GAUSSIAN" },
>     hooks = {
>         dataset = function(dctx)
>             -- dctx.subject.params: user parameters from code block attributes
>             -- dctx.data: DataManager instance for SQL queries
>             return { source = { {"x", "y"}, {1, 10}, {2, 20} } }
>         end,
>     },
> }
> ```
>
> `data_loader.load_view` resolves the hook through the host index (`host:get_hook("view", NAME, "dataset")`, already overlaid default -> model), with a loose-module fallback for non-indexed fixture views.
>
> Usage in code blocks:
> ```markdown
> ```chart:gaussian{view="gaussian" sigma=2.0}
> {...echarts config...}
> ```
> ```

> rationale: Data views separate data generation from chart configuration. This enables reusable data sources and database-driven visualizations without embedding SQL in markdown.

> status: Approved


#### HLR: Handler Caching @HLR-EXT-008

The system shall cache loaded type handlers to avoid repeated module loading.

> description: Each handler loader maintains a cache keyed by `{model}:{type_ref}`:
>
> ```lua
> local type_handlers = {}
>
> local function load_type_handler(type_ref, model_name)
>     local cache_key = model_name .. ":" .. type_ref
>     if type_handlers[cache_key] ~= nil then
>         return type_handlers[cache_key]
>     end
>
>     -- Load module via require()
>     local ok, module = pcall(require, module_path)
>     if ok and module then
>         type_handlers[cache_key] = module.handler
>         return module.handler
>     end
>
>     type_handlers[cache_key] = false  -- Cache negative result
>     return nil
> end
> ```
>
> Cache stores `false` for failed lookups to avoid repeated require() calls for non-existent modules.

> rationale: Caching improves performance for documents with many objects of the same type. Negative caching prevents repeated filesystem access for types without custom handlers.

> status: Retired

_Retired in the Host Engine Refactor: the per-(model,type) handler caches (incl. the negative cache) are replaced by the eager `(kind,id)->hook` index._

