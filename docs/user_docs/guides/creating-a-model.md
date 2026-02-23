# Guide: Creating a Custom Model

## Introduction

A **model** defines the vocabulary and behavior of your specification documents. It declares what types of spec objects exist (requirements, design items, test cases), what floats are available (diagrams, tables, code listings), how cross-references resolve, and what validation rules apply.

SpecCompiler ships with a `default` model that provides base types (SECTION, FIGURE, TABLE, PLANTUML, etc.). You create a custom model when your domain needs additional types, specialized validation, or custom rendering.

### Overlay

Models work as **overlays** on top of `default`. When you set `template: mymodel` in `project.yaml`, the engine loads types in order:

1. `models/default/types/` -- Always loaded first.
2. `models/mymodel/types/` -- Loaded second; types with the same `id` override the default.

This means your custom model only needs to define the types it adds or overrides. Everything else inherits from `default`.

## Model Directory Layout

```src:src-model-directory-layout{caption="Model directory structure"}
models/{name}/
  types/
    objects/          -- Spec object types (e.g., hlr.lua, vc.lua)
    specifications/   -- Specification types (e.g., srs.lua)
    floats/           -- Float types (e.g., figure.lua, chart.lua)
    views/            -- View types (e.g., abbrev.lua, math_inline.lua)
    relations/        -- Relation types (e.g., xref_decomposition.lua)
  proofs/             -- Validation proof queries (e.g., sd_601_*.lua)
  postprocessors/     -- Format post-processing (docx.lua, html5.lua)
  filters/            -- Pandoc Lua filters per output format
  styles/             -- Style presets (preset.lua, docx.lua, html.lua)
  data_views/         -- Chart data generators
  handlers/           -- Custom pipeline handlers
```

Only `types/` is required. All other directories are optional.

## Type Definition Pattern

Every type module is a Lua file that returns a table with two optional keys:

- A **schema key** (`M.object`, `M.float`, `M.relation`, `M.view`, or `M.specification`) that declares the type's metadata and gets registered into the database.
- An optional **`M.handler`** table that hooks into the pipeline lifecycle.

### Schema Keys by Category

```list-table:tbl-model-schema-keys{caption="Schema keys by type category"}
> header-rows: 1
> aligns: l,l,l

* - Category
  - Schema Key
  - Example File
* - Spec Objects
  - `M.object`
  - `types/objects/section.lua`
* - Floats
  - `M.float`
  - `types/floats/figure.lua`
* - Relations
  - `M.relation`
  - `types/relations/xref_citation.lua`
* - Views
  - `M.view`
  - `types/views/abbrev.lua`
* - Specifications
  - `M.specification`
  - `types/specifications/srs.lua`
```

### Handler Lifecycle

Handlers hook into pipeline phases via callback functions:

```list-table:tbl-model-handler-callbacks{caption="Handler callback functions"}
> header-rows: 1
> aligns: l,l,l

* - Callback
  - Phase
  - Purpose
* - `on_initialize`
  - INITIALIZE
  - Parse content from Pandoc AST, store in database
* - `on_analyze`
  - ANALYZE
  - Validate, resolve references, generate PIDs
* - `on_transform`
  - TRANSFORM
  - Render content, resolve external resources
* - `on_render_SpecObject`
  - EMIT
  - Convert spec object to Pandoc blocks for output
* - `on_render_Code`
  - EMIT
  - Convert inline code to Pandoc inlines (views)
* - `on_render_CodeBlock`
  - EMIT
  - Convert code block to Pandoc blocks (floats)
```

The `prerequisites` field controls execution order: a handler with `prerequisites = {"spec_views"}` runs after the `spec_views` handler.

## Walkthrough: Custom Object Type

This example creates a High-Level Requirement (HLR) type with required attributes.

### Step 1: Create the Type File

Create `models/mymodel/types/objects/hlr.lua`:

```src.lua:src-model-object-type{caption="Custom object type: hlr.lua"}
local M = {}

M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    description = "A top-level system requirement",
    pid_prefix = "HLR",           -- Auto-PID prefix
    pid_format = "%s-%03d",       -- Produces HLR-001, HLR-002, etc.
    attributes = {
        {
            name = "priority",
            type = "ENUM",
            values = { "High", "Medium", "Low" },
            min_occurs = 1,       -- Required
            max_occurs = 1,
        },
        {
            name = "status",
            type = "ENUM",
            values = { "Draft", "Approved", "Implemented" },
            min_occurs = 1,
            max_occurs = 1,
        },
        {
            name = "rationale",
            type = "XHTML",       -- Rich text
            min_occurs = 0,       -- Optional
        },
    },
}

return M
```

### Step 2: Use in Markdown

```src.markdown:src-model-object-usage{caption="Using the custom object type"}
## hlr: User Authentication @HLR-001

> priority: High

> status: Draft

> rationale: Required by security policy section 4.2

The system shall authenticate users via username and password.
```

### Step 3: Add a Handler (Optional)

If the type needs custom behavior during pipeline phases, add `M.handler`:

```src.lua:src-model-object-handler{caption="Object type with handler"}
local Queries = require("db.queries")

M.handler = {
    name = "hlr_handler",
    prerequisites = {},

    on_analyze = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local spec_id = ctx.spec_id or "default"
            local objects = data:query_all(
                Queries.content.objects_by_spec_type,
                { spec_id = spec_id, type_ref = "HLR" }
            )
            for _, obj in ipairs(objects or {}) do
                -- Custom validation logic here
            end
        end
    end,
}
```

### Object Schema Fields Reference

```list-table:tbl-model-object-fields{caption="Object schema fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `id`
  - string
  - required
  - Unique identifier (uppercase convention)
* - `long_name`
  - string
  - same as `id`
  - Human-readable name
* - `description`
  - string
  - `""`
  - Description text
* - `extends`
  - string
  - nil
  - Base type for inheritance
* - `is_default`
  - boolean
  - false
  - If true, headers without explicit type match this
* - `is_composite`
  - boolean
  - false
  - Composite object flag
* - `pid_prefix`
  - string
  - nil
  - Prefix for auto-generated PIDs
* - `pid_format`
  - string
  - nil
  - Printf format string for PIDs
* - `aliases`
  - list
  - nil
  - Alternative identifiers for syntax matching
* - `attributes`
  - list
  - nil
  - Attribute definitions (see Attribute Schema)
```

### Attribute Schema

```list-table:tbl-model-attribute-fields{caption="Attribute definition fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `name`
  - string
  - required
  - Attribute identifier
* - `type`
  - string
  - `"STRING"`
  - Datatype: STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML
* - `min_occurs`
  - integer
  - 0
  - Minimum values (0 = optional, 1 = required)
* - `max_occurs`
  - integer
  - 1
  - Maximum values
* - `min_value`
  - number
  - nil
  - Lower bound for numeric types
* - `max_value`
  - number
  - nil
  - Upper bound for numeric types
* - `values`
  - list
  - nil
  - Valid enum values (required when `type = "ENUM"`)
* - `datatype_ref`
  - string
  - nil
  - Explicit datatype ID (overrides auto-generated)
```

## Walkthrough: Custom Float Type

Floats are numbered elements declared in fenced code blocks. This example creates a custom float type for diagrams.

### Step 1: Create the Type File

Create `models/mymodel/types/floats/sequence_diagram.lua`:

```src.lua:src-model-float-type{caption="Custom float type: sequence_diagram.lua"}
local M = {}

M.float = {
    id = "SEQUENCE",
    long_name = "Sequence Diagram",
    description = "UML Sequence Diagram rendered via PlantUML",
    caption_format = "Figure",        -- Caption prefix in output
    counter_group = "FIGURE",         -- Shares counter with FIGURE, PLANTUML
    aliases = { "seq", "sequence" },  -- Syntax: ```seq:label or ```sequence:label
    needs_external_render = true,     -- Requires external tool
}

return M
```

### Float Schema Fields Reference

```list-table:tbl-model-float-fields{caption="Float schema fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `id`
  - string
  - required
  - Unique identifier (uppercase)
* - `caption_format`
  - string
  - same as `id`
  - Prefix used in output captions
* - `counter_group`
  - string
  - same as `id`
  - Counter sharing group (e.g., FIGURE, TABLE)
* - `aliases`
  - list
  - nil
  - Alternative syntax identifiers
* - `needs_external_render`
  - boolean
  - false
  - Whether rendering requires an external tool
* - `style_id`
  - string
  - nil
  - Custom style identifier for output formatting
```

### Counter Groups

Multiple float types can share a numbering sequence by using the same `counter_group`. For example, FIGURE, PLANTUML, and CHART all use `counter_group = "FIGURE"`, so they are numbered sequentially as Figure 1, Figure 2, Figure 3 regardless of which specific type each is.

## Walkthrough: Float with External Rendering

When a float type needs an external tool to produce its output (PlantUML for diagrams, Deno for charts, etc.), it uses the **external render handler**. This handler collects all items that need rendering, spawns external processes in parallel, and dispatches results back to type-specific callbacks.

### How External Rendering Works

The pipeline flow for external renders:

1. **INITIALIZE** -- The float is parsed from the Markdown code block and stored in `spec_floats` with `raw_content`.
2. **TRANSFORM** -- The external render handler (`src/pipeline/transform/external_render_handler.lua`) queries all floats where `needs_external_render = 1` and `resolved_ast IS NULL`.
3. **Prepare** -- For each float, the handler calls the registered `prepare_task` callback, which writes input files and builds a command descriptor.
4. **Cache check** -- If `output_path` exists on disk (from a previous build), the task is skipped and `handle_result` is called immediately with the cached path.
5. **Batch spawn** -- All non-cached tasks are spawned in parallel via `task_runner.spawn_batch`.
6. **Dispatch** -- Results (stdout, stderr, exit code) are dispatched to each type's `handle_result` callback, which updates `resolved_ast` in the database.

### Registering a Renderer

External renderers are registered at module load time by calling `external_render.register_renderer(type_ref, callbacks)`. The callbacks table must provide two functions:

```list-table:tbl-model-render-callbacks{caption="External render callback functions"}
> header-rows: 1
> aligns: l,l

* - Callback
  - Signature and Purpose
* - `prepare_task`
  - `function(float, build_dir, log, data, model_name) -> task|nil` -- Writes input files, builds command descriptor. Returns nil to skip rendering.
* - `handle_result`
  - `function(task, success, stdout, stderr, data, log)` -- Processes output. Updates `resolved_ast` in the database via `float_base.update_resolved_ast`.
```

### Task Descriptor

The `prepare_task` callback returns a task descriptor table:

```list-table:tbl-model-task-descriptor{caption="Task descriptor fields"}
> header-rows: 1
> aligns: l,l,l

* - Field
  - Type
  - Description
* - `cmd`
  - string
  - Command to execute (e.g., `"plantuml"`, `"deno"`)
* - `args`
  - list
  - Command arguments
* - `opts`
  - table
  - Options: `cwd` (working directory), `timeout` (milliseconds)
* - `output_path`
  - string
  - Expected output file path; if it exists, the task is skipped (cache hit)
* - `context`
  - table
  - Arbitrary data passed through to `handle_result` (float record, hash, paths, etc.)
```

### Example: PlantUML Renderer

The built-in PlantUML renderer demonstrates the full pattern:

```src.lua:src-model-external-render-plantuml{caption="PlantUML external renderer (simplified)"}
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")
local external_render = require("pipeline.transform.external_render_handler")

local M = {}

M.float = {
    id = "PLANTUML",
    long_name = "PlantUML Diagram",
    caption_format = "Figure",
    counter_group = "FIGURE",
    aliases = { "puml", "plantuml", "uml" },
    needs_external_render = true,   -- Enables external render pipeline
}

external_render.register_renderer("PLANTUML", {
    prepare_task = function(float, build_dir, log)
        local content = float.raw_content or ''
        -- Ensure @startuml/@enduml wrapper
        if not content:match('@startuml') then
            content = '@startuml\n' .. content .. '\n@enduml'
        end

        local hash = pandoc.sha1(content)
        local diagrams_path = build_dir .. "/diagrams"
        local puml_file = diagrams_path .. "/" .. hash .. ".puml"
        local png_file = diagrams_path .. "/" .. hash .. ".png"

        task_runner.ensure_dir(diagrams_path)
        task_runner.write_file(puml_file, content)

        return {
            cmd = "plantuml",
            args = { "-tpng", puml_file },
            opts = { timeout = 30000 },
            output_path = png_file,       -- Cache key: skip if PNG exists
            context = {
                hash = hash,
                float = float,
                relative_path = "diagrams/" .. hash .. ".png",
            }
        }
    end,

    handle_result = function(task, success, stdout, stderr, data, log)
        local ctx = task.context
        if not success then
            log.warn("PlantUML failed for %s: %s",
                ctx.float.identifier:sub(1,12), stderr)
            return
        end

        -- Store resolved path as JSON in resolved_ast
        local json = string.format(
            '{"png_paths":["%s"]}',
            ctx.relative_path
        )
        float_base.update_resolved_ast(data, ctx.float.identifier, json)
    end
})

return M
```

### Example: Chart Renderer with Data Injection

The chart renderer adds a data injection step before rendering, loading data views from `models/{model}/data_views/`:

```src.lua:src-model-external-render-chart{caption="Chart external renderer (simplified)"}
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")
local data_loader = require("core.data_loader")
local external_render = require("pipeline.transform.external_render_handler")

local M = {}

M.float = {
    id = "CHART",
    long_name = "Chart",
    caption_format = "Figure",
    counter_group = "FIGURE",
    aliases = { "echarts", "echart" },
    needs_external_render = true,
}

external_render.register_renderer("CHART", {
    prepare_task = function(float, build_dir, log, data, model_name)
        local attrs = float_base.decode_attributes(float)
        local json_content = float.raw_content or '{}'

        -- Data injection: load view module and merge data into ECharts config
        local view_name = attrs.view
        if view_name and data then
            local inject_attrs = { view = view_name, model = model_name }
            local config = pandoc.json.decode(json_content)
            local injected = data_loader.inject_chart_data(
                config, inject_attrs, data, log)
            if injected then
                json_content = pandoc.json.encode(injected)
            end
        end

        local hash = pandoc.sha1(json_content)
        local charts_path = build_dir .. "/charts"
        local json_file = charts_path .. "/" .. hash .. ".json"
        local png_file = charts_path .. "/" .. hash .. ".png"

        task_runner.ensure_dir(charts_path)
        task_runner.write_file(json_file, json_content)

        return {
            cmd = "deno",
            args = {
                "run", "--allow-read", "--allow-write", "--allow-env",
                "echarts-render.ts", json_file, png_file,
                tostring(attrs.width or 600),
                tostring(attrs.height or 400)
            },
            opts = { timeout = 60000 },
            output_path = png_file,
            context = {
                hash = hash,
                float = float,
                relative_path = "charts/" .. hash .. ".png",
            }
        }
    end,

    handle_result = function(task, success, stdout, stderr, data, log)
        local ctx = task.context
        if not success then
            log.warn("Chart render failed: %s", stderr)
            return
        end

        local json = string.format('{"png_path":"%s"}', ctx.relative_path)
        float_base.update_resolved_ast(data, ctx.float.identifier, json)
    end
})

return M
```

### Creating Your Own External Renderer

To create a float type that uses an external tool:

1. **Set `needs_external_render = true`** in the float schema.
2. **Register callbacks** with `external_render.register_renderer("YOUR_TYPE", { ... })` at module load time (top-level code, not inside a function).
3. **In `prepare_task`**: Write input content to a temporary file, build the command and arguments, and return a task descriptor with `output_path` for file-based caching.
4. **In `handle_result`**: Parse the output (stdout, generated files), serialize the result as JSON, and call `float_base.update_resolved_ast(data, identifier, json)` to store it.
5. **Do not define `M.handler.on_transform`** -- the external render handler orchestrates the TRANSFORM phase for all registered types. Defining your own `on_transform` would bypass the parallel batch execution.

Key utilities available:

```list-table:tbl-model-render-utilities{caption="Utility functions for external renderers"}
> header-rows: 1
> aligns: l,l

* - Function
  - Purpose
* - `task_runner.ensure_dir(path)`
  - Create directory if it does not exist
* - `task_runner.write_file(path, content)`
  - Write content to a file; returns `ok, err`
* - `task_runner.file_exists(path)`
  - Check if a file exists on disk
* - `task_runner.command_exists(cmd)`
  - Check if a command is available in PATH
* - `float_base.decode_attributes(float)`
  - Parse float's `pandoc_attributes` JSON into a Lua table
* - `float_base.update_resolved_ast(data, id, json)`
  - Store the rendering result in the database
```

### File-Based Caching

The external render handler provides automatic file-based caching via the `output_path` field in the task descriptor. If the output file already exists on disk when `prepare_task` returns, the handler skips spawning the external process and immediately calls `handle_result` with empty stdout/stderr. This means:

- The content hash should be part of the output filename (e.g., `diagrams/{sha1}.png`) so that content changes produce a new filename and trigger re-rendering.
- The `handle_result` callback should work correctly whether called after a fresh render or a cache hit (it receives the same `task.context`).
- Deleting the output files forces re-rendering on the next build (the database `resolved_ast` is also cleared during INITIALIZE).

### External Rendering for Views

The same `external_render.register_renderer` mechanism works for views that need external tools. For example, `math_inline.lua` registers a renderer for the `MATH_INLINE` view type to convert AsciiMath to MathML/OMML via an external script. The handler queries `spec_views` (instead of `spec_floats`) with `needs_external_render = 1` and dispatches to the same callback interface.

## Walkthrough: Custom Relation with Inference Rules

Relations connect spec objects via link syntax. The relation resolver uses specificity scoring to infer the relation type.

### Step 1: Create the Type File

Create `models/mymodel/types/relations/traces_to.lua`:

```src.lua:src-model-relation-type{caption="Custom relation type: traces_to.lua"}
local M = {}

M.relation = {
    id = "TRACES_TO",
    long_name = "Traces To",
    description = "Traceability link from LLR to HLR",
    link_selector = "@",             -- Uses [PID](@) syntax
    source_type_ref = "LLR",        -- Only from LLR objects
    target_type_ref = "HLR",        -- Only to HLR objects
    aliases = nil,                   -- No alias prefix
    is_default = false,
}

return M
```

### Step 2: Use in Markdown

```src.markdown:src-model-relation-usage{caption="Using the relation type"}
### llr: Password Length Check @LLR-001

Passwords must be at least 8 characters. Traces to [HLR-001](@).
```

### Inference Scoring

When multiple relation types could match a link, the resolver scores each candidate:

```list-table:tbl-model-inference-scoring{caption="Inference scoring dimensions"}
> header-rows: 1
> aligns: l,c,l,c

* - Dimension
  - Match
  - Constraint mismatch
  - No constraint (NULL)
* - **Selector** (`@` or `#`)
  - +1
  - Eliminated
  - +0
* - **Source attribute**
  - +1
  - Eliminated
  - +0
* - **Source type**
  - +1
  - Eliminated
  - +0
* - **Target type**
  - +1
  - Eliminated
  - +0
```

The highest-scoring candidate wins. If two candidates tie, the relation is flagged as ambiguous (`relation_ambiguous`). Constraints set to `nil` act as wildcards (+0) rather than eliminating the candidate.

### Relation Schema Fields Reference

```list-table:tbl-model-relation-fields{caption="Relation schema fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `id`
  - string
  - required
  - Unique identifier (uppercase)
* - `link_selector`
  - string
  - nil
  - Required selector: `"@"` for PID refs, `"#"` for label refs
* - `source_type_ref`
  - string
  - nil
  - Constrain source to this object type (nil = any)
* - `target_type_ref`
  - string
  - nil
  - Constrain target to this object type (nil = any)
* - `source_attribute`
  - string
  - nil
  - Constrain to links within this attribute context
* - `aliases`
  - list
  - nil
  - Prefix aliases for `[alias:key](#)` syntax
* - `is_default`
  - boolean
  - false
  - Default relation for its selector when no better match
```

### Relations with Handlers

A relation type can include a handler for custom transform behavior. For example, `xref_citation.lua` rewrites citation links to Pandoc `Cite` elements during the TRANSFORM phase:

```src.lua:src-model-relation-handler{caption="Relation type with handler"}
M.handler = {
    name = "my_relation_handler",
    prerequisites = {"spec_relations"},  -- Run after relations are stored

    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            -- Custom transform logic
        end
    end
}
```

### Base Types and Inheritance

Relation types support inheritance via base types. Instead of repeating `link_selector` and resolution logic in every type, you extend a base type:

- **`traceable`** (`models/default/types/relations/traceable.lua`) — base for `@` (PID) selector
- **`xref`** (`models/default/types/relations/xref.lua`) — base for `#` (label) selector

Use `extend()` to create a concrete type:

```src.lua:src-model-extend-traceable{caption="Extending the traceable base type"}
local traceable = require("models.default.types.relations.traceable")
local M = {}

M.relation = traceable.extend({
    id = "TRACES_TO",
    long_name = "Traces To",
    description = "Traceability link from one object to another",
})

return M
```

The `extend()` call inherits `link_selector = "@"` from the base and merges your overrides. For `#` selector types, use `xref.extend()` instead.

### Custom Link Display Text

By default, object references display the target's PID and float references display the caption format with the float number (e.g., "Figure 3"). To customize display text, add a standard `M.handler` with an `on_transform` hook using the shared `link_rewrite_utils` utility:

```src.lua:src-model-display-text-dic{caption="Custom display text via on_transform"}
local traceable = require("models.default.types.relations.traceable")
local link_rewrite = require("pipeline.shared.link_rewrite_utils")
local M = {}

M.relation = traceable.extend({
    id = "XREF_DIC",
    long_name = "Dictionary Reference",
    description = "Cross-reference to a dictionary entry",
    target_type_ref = "DIC",
})

M.handler = {
    name = "xref_dic_handler",
    prerequisites = {"spec_relations"},
    on_transform = function(data, contexts, _diagnostics)
        link_rewrite.rewrite_display_for_type(data, contexts, "XREF_DIC", function(target)
            if target.title_text and target.title_text ~= "" then
                return target.title_text
            end
        end)
    end
}

return M
```

A link `[DIC-AUTH-001](@)` would display as "Authentication" instead of "DIC-AUTH-001".

The `display_fn` receives a `target` table with fields `pid`, `type_ref`, and `title_text`. Return a string for custom display text, or `nil` to keep the default.

## Walkthrough: Custom View

Views are inline elements declared with backtick syntax (`` `prefix: content` ``).

### Step 1: Create the Type File

Create `models/mymodel/types/views/symbol.lua`:

```src.lua:src-model-view-type{caption="Custom view type: symbol.lua"}
local M = {}
local Queries = require("db.queries")

M.view = {
    id = "SYMBOL",
    long_name = "Symbol",
    description = "Engineering symbol with unit definition",
    aliases = { "sym" },
    inline_prefix = "symbol",         -- Enables `symbol: content` syntax
    needs_external_render = false,
}

M.handler = {
    name = "symbol_handler",
    prerequisites = {"spec_views"},

    on_initialize = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local doc = ctx.doc
            if not doc or not doc.blocks then goto continue end

            local spec_id = ctx.spec_id or "default"
            local file_seq = 0

            local visitor = {
                Code = function(c)
                    local content = (c.text or ""):match("^symbol:%s*(.+)$")
                        or (c.text or ""):match("^sym:%s*(.+)$")
                    if not content then return nil end

                    file_seq = file_seq + 1
                    local identifier = pandoc.sha1(spec_id .. ":" .. file_seq .. ":" .. content)

                    data:execute(Queries.content.insert_view, {
                        identifier = identifier,
                        specification_ref = spec_id,
                        view_type_ref = "SYMBOL",
                        from_file = ctx.source_path or "unknown",
                        file_seq = file_seq,
                        raw_ast = content
                    })
                end
            }

            for _, block in ipairs(doc.blocks) do
                pandoc.walk_block(block, visitor)
            end
            ::continue::
        end
    end,

    on_render_Code = function(code, ctx)
        local content = (code.text or ""):match("^symbol:%s*(.+)$")
            or (code.text or ""):match("^sym:%s*(.+)$")
        if not content then return nil end

        -- Render as emphasized text
        return { pandoc.Emph({ pandoc.Str(content) }) }
    end,
}

return M
```

### Step 2: Use in Markdown

```src.markdown:src-model-view-usage{caption="Using the custom view type"}
The force is defined as `symbol: F = ma` where `symbol: F` is force in Newtons.
```

### View Schema Fields Reference

```list-table:tbl-model-view-fields{caption="View schema fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `id`
  - string
  - required
  - Unique identifier (uppercase)
* - `inline_prefix`
  - string
  - nil
  - Prefix for inline code dispatch (e.g., `"math"` enables `math:` syntax)
* - `aliases`
  - list
  - nil
  - Alternative prefixes for the same view type
* - `needs_external_render`
  - boolean
  - false
  - Whether rendering requires an external tool (batch processing)
* - `materializer_type`
  - string
  - nil
  - Materializer strategy (e.g., 'toc', 'lof', 'custom')
* - `counter_group`
  - string
  - nil
  - Counter group for numbered views
```

## Validation Proofs

Proofs are SQL-based validation rules that run during the VERIFY phase. Each proof creates a SQL view; if the view returns any rows, those rows represent violations.

### Proof File Pattern

Create `models/mymodel/proofs/vc_missing_hlr_traceability.lua`:

```src.lua:src-model-proof{caption="Validation proof module"}
local M = {}

M.proof = {
    view = "view_traceability_vc_missing_hlr",
    policy_key = "traceability_vc_to_hlr", -- Key in project.yaml validation section
    sql = [[
CREATE VIEW IF NOT EXISTS view_traceability_vc_missing_hlr AS
SELECT
  vc.identifier AS object_id,
  vc.pid AS object_pid,
  vc.title_text AS object_title,
  vc.from_file,
  vc.start_line
FROM spec_objects vc
WHERE vc.type_ref = 'VC'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects target ON target.identifier = r.target_ref
    WHERE r.source_ref = vc.identifier
      AND target.type_ref = 'HLR'
  );
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Verification case '%s' has no traceability link to an HLR",
            label
        )
    end
}

return M
```

### Proof Schema

```list-table:tbl-model-proof-fields{caption="Proof module fields"}
> header-rows: 1
> aligns: l,l,l

* - Field
  - Type
  - Description
* - `view`
  - string
  - SQL view name (must match the CREATE VIEW name)
* - `policy_key`
  - string
  - Key for suppression in `project.yaml` validation section
* - `sql`
  - string
  - SQL CREATE VIEW statement; rows returned = violations
* - `message`
  - function
  - Takes a row table, returns a diagnostic message string
```

### Suppressing Proofs

Users suppress proofs in `project.yaml` using the `policy_key`:

```src.yaml:src-model-suppress-proof{caption="Suppressing a validation proof"}
validation:
  traceability_vc_to_hlr: ignore   # Suppress this proof
```

## Model Overlay/Extension Pattern

### How Overlays Work

The type loader (`src/core/type_loader.lua`) loads models in two passes:

1. **Default model**: Scans `models/default/types/{category}/` and registers all types.
2. **Custom model**: Scans `models/{template}/types/{category}/` and registers all types.

Since type registration uses `INSERT OR REPLACE`, a custom model type with the same `id` as a default type replaces it entirely. Types with new IDs are added alongside the defaults.

### Path Resolution

The loader resolves model paths in order:

1. `$SPECCOMPILER_HOME/models/{name}/types/` (Docker/production)
2. `./models/{name}/types/` (local development)

### Partial Customization Example

A model that only adds an HLR type and a custom proof:

```src:src-model-minimal-overlay{caption="Minimal overlay model"}
models/mymodel/
  types/
    objects/
      hlr.lua         -- Adds HLR type (default has no HLR)
    relations/
      traces_to.lua   -- Adds traceability relation
  proofs/
    sd_601_vc_missing_hlr.lua  -- Domain-specific validation
```

All other types (SECTION, FIGURE, TABLE, etc.) are inherited from `default`.

## project.yaml Integration

Set the `template` field to use your custom model:

```src.yaml:src-model-project-yaml{caption="Using a custom model in project.yaml"}
project:
  code: MYPROJ
  name: My Project

template: mymodel   # Loads models/default/ then models/mymodel/

doc_files:
  - srs.md
```
