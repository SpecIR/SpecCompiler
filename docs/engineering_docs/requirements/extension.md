## Extension Requirements

### SF: Extension Framework @SF-005

Model-based extensibility for type [TERM-16](@), renderers, and [TERM-35](@).

> description: Groups requirements for the extension mechanism that enables custom models
> to provide type handlers, [TERM-34](@), data view generators, and style presets.

> rationale: Extensibility through model directories enables domain-specific customization
> without modifying the core pipeline.

### HLR: Model-Specific Type Handler Loading @HLR-EXT-001

The system shall load type-specific handlers from model directories.

> description: Type handlers control how specification content is rendered during the [TERM-22](@) phase. The loading mechanism supports:
>
> - **Object types**: Loaded from `models/{model}/types/objects/{type}.lua`
> - **Specification types**: Loaded from `models/{model}/types/specifications/{type}.lua`
> - **Float types**: Loaded from `models/{model}/types/floats/{type}.lua`
> - **View types**: Loaded from `models/{model}/types/views/{type}.lua`
>
> Module loading uses `require()` with path `models.{model}.types.{category}.{type}`. Type names are converted to lowercase for file lookup (e.g., "HLR" -> "hlr.lua").

> rationale: Separating type handlers into model directories enables domain-specific customization. Organizations can define their own requirement types, document types, and rendering behavior without modifying core code.

> status: Approved

> belongs_to: [SF-005](@)

### HLR: Model Directory Structure @HLR-EXT-002

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
>   data_views/      -- Data view generators for chart data injection
>   filters/         -- Pandoc filters (docx.lua, html.lua, markdown.lua)
>   postprocessors/  -- Format-specific postprocessors
>   styles/          -- Style presets and templates
> ```
>
> Model names are referenced via project configuration `template` field or context `model_name`. The "default" model provides base implementations with fallback behavior.

> rationale: Standardized structure enables consistent discovery of type modules across models and provides clear extension points for each content category.

> status: Approved

> belongs_to: [SF-005](@)

### HLR: Handler Registration Interface @HLR-EXT-003

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

> belongs_to: [SF-005](@)

### HLR: Type Definition Schema @HLR-EXT-004

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

> belongs_to: [SF-005](@)

### HLR: Model Path Resolution @HLR-EXT-005

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

> status: Approved

> belongs_to: [SF-005](@)

### HLR: External Renderer Registration @HLR-EXT-006

External renderers shall register callbacks for task preparation and result handling.

> description: Float types requiring external tools (PlantUML, ECharts, etc.) register with the external render handler:
>
> ```lua
> external_render.register_renderer("PLANTUML", {
>     prepare_task = function(float, build_dir, log, data, model_name)
>         -- Return task descriptor with cmd, args, output_path, context
>     end,
>     handle_result = function(task, success, stdout, stderr, data, log)
>         -- Update resolved_ast in database
>     end
> })
> ```
>
> The core orchestrates: query items -> prepare tasks -> cache filter -> batch spawn -> dispatch results. This enables parallel execution across all external renders.

> rationale: Registration pattern decouples type-specific rendering logic from core orchestration. Callbacks enable types to control task preparation and result interpretation while core handles parallelization and caching.

> status: Approved

> belongs_to: [SF-005](@)

### HLR: Data View Generator Loading @HLR-EXT-007

The system shall load data view generators from model directories for chart data injection.

> description: Data views are Lua modules that generate data for charts:
>
> ```lua
> -- models/{model}/data_views/{view_name}.lua
> local M = {}
>
> function M.generate(params, data)
>     -- params: user parameters from code block attributes
>     -- data: DataManager instance for SQL queries
>     return { source = { {"x", "y"}, {1, 10}, {2, 20} } }
> end
>
> return M
> ```
>
> Views are loaded via `data_loader.load_view(view_name, model_name, data, params)`. Resolution tries the specified model first, then falls back to default.
>
> Usage in code blocks:
> ```markdown
> ```chart:gaussian{view="gaussian" sigma=2.0}
> {...echarts config...}
> ```
> ```

> rationale: Data views separate data generation from chart configuration. This enables reusable data sources and database-driven visualizations without embedding SQL in markdown.

> status: Approved

> belongs_to: [SF-005](@)

### HLR: Handler Caching @HLR-EXT-008

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

> status: Approved

> belongs_to: [SF-005](@)
