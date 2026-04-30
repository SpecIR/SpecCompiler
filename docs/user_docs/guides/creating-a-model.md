# Guide: Creating a Custom Model

## Introduction

A **model** defines the vocabulary and behaviour of your specification documents. It declares what object types exist (requirements, design items, test cases), what floats are available (diagrams, tables, code listings), how cross-references resolve, and what validation rules apply.

SpecCompiler ships with a `default` model that provides base types (SECTION, FIGURE, TABLE, PLANTUML, …). You create a custom model when your domain needs additional types, specialised rendering, or extra validation.

## Quick-start template

Every type module has the same shape. Copy this skeleton and keep only what you need:

```src.lua:src-model-quickstart{caption="The full type-module contract, annotated"}
-- File: models/<your-model>/types/<category>/<type-name>.lua
local M = {}

-- Declarative metadata: picked up by the type loader and written into
-- the SpecIR database. Exactly one of these keys per module.
M.object        = { id = "...", ... }   -- or M.float / M.relation / M.view / M.specification

-- Optional behaviour. Two kinds of callbacks live here (see Handler Contract):
--   * on_<phase>(...)           -- pipeline phase hook (on_initialize, on_transform, ...)
--   * on_render_<Thing>(...)    -- decorated per-item callback (on_render_SpecObject,
--                                  on_render_Link, on_render_Code, ...)
M.handler = {
    name = "my_handler",        -- required and unique across all handlers
    -- prerequisites = { ... }, -- optional; only needed to order phase hooks
    -- on_analyze = function(data, contexts, diagnostics) ... end,
    -- on_render_SpecObject = function(obj, ctx) ... end,
}

return M
```

Set `template: <your-model>` in `project.yaml` (see [Project Integration](#project-integration)) and `specc build` will load your types on top of `default`.

## Overlay

Models layer as **overlays** on top of `default`. When `project.yaml` sets `template: mymodel`, the loader runs two passes:

1. `models/default/types/` — loaded first.
2. `models/mymodel/types/` — loaded second; a type whose `id` matches a default replaces the default entirely.

Types with new `id`s are added alongside the defaults. Everything you don't redefine is inherited.

## Directory layout

```src:src-model-directory-layout{caption="Model directory structure"}
models/<your-model>/
  types/
    objects/          -- Spec object types  (e.g., hlr.lua, vc.lua)
    specifications/   -- Specification types (e.g., srs.lua)
    floats/           -- Float types         (e.g., sequence_diagram.lua)
    views/            -- View types          (e.g., symbol.lua)
    relations/        -- Relation types      (e.g., traces_to.lua)
  verification_views/             -- Verification views   (e.g., vc_missing_hlr.lua)
  postprocessors/     -- Per-format post-processing (docx.lua, html5.lua)
  filters/            -- Pandoc Lua filters per output format
  styles/             -- Style presets (preset.lua, docx.lua, html.lua)
  data_views/         -- Chart data generators
  handlers/           -- Extra pipeline handlers not tied to a type
```

Only `types/` is required; everything else is optional.

The loader supports both single files (`types/floats/figure.lua`) and subdirectories with an `init.lua` (`types/floats/figure/init.lua`) — useful when a type needs helper modules alongside it.

## Type categories at a glance

```list-table:tbl-model-categories{caption="Type categories, schema keys, and which handler callbacks apply"}
> header-rows: 1
> aligns: l,l,l,l

* - Category
  - Schema key
  - Example file
  - Handler callbacks typically used
* - Spec object
  - `M.object`
  - `types/objects/hlr.lua`
  - `on_render_SpecObject`
* - Float
  - `M.float`
  - `types/floats/figure.lua`
  - `on_render_CodeBlock` (or external renderer)
* - Relation
  - `M.relation`
  - `types/relations/traces_to.lua`
  - `on_render_Link`
* - View
  - `M.view`
  - `types/views/abbrev.lua`
  - `on_render_Code`
* - Specification
  - `M.specification`
  - `types/specifications/srs.lua`
  - `on_initialize`, `on_analyze`
```

## Handler contract

`M.handler` is the single behaviour surface for every type. Two kinds of callbacks live on it:

**Phase hooks** run once per pipeline phase. They see the full context and are ordered via `prerequisites`.

**Decorated per-item callbacks** are dispatched inline by a phase hook (e.g. the spec-object renderer) with the specific item being processed and a pre-resolved context. They do **not** need `prerequisites` because they don't participate in phase ordering — they run wherever their dispatching phase runs.

```list-table:tbl-model-handler-callbacks{caption="Handler callbacks, signatures, and when they fire"}
> header-rows: 1
> aligns: l,l,l,l

* - Callback
  - Kind
  - Signature
  - Purpose
* - `on_initialize`
  - Phase hook
  - `(data, contexts, diagnostics)`
  - Parse content from the Pandoc AST, store in SpecIR.
* - `on_analyze`
  - Phase hook
  - `(data, contexts, diagnostics)`
  - Validate, resolve references, generate PIDs.
* - `on_transform`
  - Phase hook
  - `(data, contexts, diagnostics)`
  - Rewrite content, resolve external resources.
* - `on_render_SpecObject`
  - Decorated
  - `(obj, ctx)`
  - Produce Pandoc blocks for a spec object.
* - `on_render_Link`
  - Decorated
  - `(target, ctx) -> string|nil`
  - Return the display text for a link to an object/float of this relation type. `nil` falls through to the base type.
* - `on_render_Code`
  - Decorated
  - `(code, ctx)`
  - Produce Pandoc inlines for an inline view (`` `prefix: content` ``).
* - `on_render_CodeBlock`
  - Decorated
  - `(block, ctx)`
  - Produce Pandoc blocks for a float code block.
```

**What's in `ctx` for decorated callbacks**

```list-table:tbl-model-ctx-fields{caption="Pre-resolved fields on ctx"}
> header-rows: 1
> aligns: l,l

* - Field
  - Meaning
* - `ctx.attributes`
  - Object-level attributes (map of lowercase name -> `{ value, ast }`). Already queried by the pipeline.
* - `ctx.spec_attributes`
  - Specification-level attributes (map of lowercase name -> string). Cached per spec across objects.
* - `ctx.spec_id`
  - Specification identifier.
* - `ctx.output_format`
  - Target format (`docx`, `html5`, `gfm`, `json`).
* - `ctx.original_blocks`
  - The decoded source blocks, with headers / attribute blockquotes filtered out. Fall back to these when required inputs are missing.
* - `ctx.db`
  - `DataManager` — only needed for custom queries. Prefer the pre-resolved fields above.
```

> If you catch yourself starting a decorated callback with a DB query for "the thing I'm rendering", check whether the pipeline already exposes it on `ctx`. Decoration exists so handlers don't carry query boilerplate.

## Five canonical templates

### Object type

Create an object type with required attributes and a custom render:

```src.lua:src-model-template-object{caption="types/objects/hlr.lua"}
local render_utils = require("pipeline.shared.render_utils")
local M = {}

M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    description = "A top-level system requirement",
    pid_prefix = "HLR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "priority", type = "ENUM",
          values = { "High", "Medium", "Low" },
          min_occurs = 1, max_occurs = 1 },
        { name = "rationale", type = "XHTML" },
    },
}

M.handler = {
    name = "hlr_handler",
    on_render_SpecObject = function(obj, ctx)
        -- obj is the SpecObject row; ctx.attributes is already loaded.
        local priority = (ctx.attributes.priority or {}).value or "?"
        local blocks = {}
        render_utils.add_header_blocks(blocks, ctx.header_level,
            obj.pid .. ": " .. (obj.title_text or ""))
        table.insert(blocks, pandoc.Para({
            pandoc.Strong({ pandoc.Str("Priority: ") }),
            pandoc.Str(priority),
        }))
        render_utils.add_blocks(blocks, ctx.original_blocks)
        return blocks
    end,
}

return M
```

Usage:

```src.markdown:src-model-template-object-usage{caption="Authoring an HLR in Markdown"}
## hlr: User Authentication @HLR-001

> priority: High
> rationale: Required by security policy section 4.2

The system shall authenticate users via username and password.
```

Most object types don't need a custom `on_render_SpecObject` — the shared `spec_object_base.create_handler(name)` factory produces a vanilla PID-header / attributes / body renderer. Reach for a custom handler only when the default layout isn't what you want.

### Relation type

The common case is a simple subtype that narrows a base relation (`PID_REF` for `@` or `LABEL_REF` for `#`):

```src.lua:src-model-template-relation-simple{caption="types/relations/traces_to.lua"}
local M = {}

M.relation = {
    id = "TRACES_TO",
    extends = "PID_REF",
    long_name = "Traces To",
    description = "Traceability link from one object to another",
    source_type_ref = "LLR",
    target_type_ref = "HLR",
}

return M
```

That's complete. The link `[HLR-001](@)` written inside an LLR will resolve as `TRACES_TO`.

When the default display text (PID for objects, `"<caption> <number>"` for floats) isn't right, add `on_render_Link`:

```src.lua:src-model-template-relation-display{caption="Custom display text via on_render_Link"}
M.handler = {
    name = "xref_sec_handler",
    -- Render section refs as "<hierarchical-number> <title>", e.g. "3.4 Introduction".
    on_render_Link = function(target, _ctx)
        local title = target.title or ""
        local number = target.pid and target.pid:match("sec([%d%.]+)$")
        if number and title ~= "" then return number .. " " .. title end
        if title ~= "" then return title end
        return target.pid
    end,
}
```

`target` is pre-resolved. Object targets carry `{ kind = "object", pid, title, spec, type_ref }`; float targets carry `{ kind = "float", label, anchor, number, caption, spec }`. Return a string to override the display text, or `nil` to let the base type's handler take over.

`LABEL_REF` and `PID_REF` each ship with a default `on_render_Link` (title for sections, PID for other objects, `"<caption> <number>"` for floats). Concrete types inherit this automatically via `extends`, so you only write `on_render_Link` when you want something different.

### View type

Views are inline elements written with backtick syntax (`` `prefix: content` ``).

```src.lua:src-model-template-view{caption="types/views/symbol.lua"}
local M = {}

M.view = {
    id = "SYMBOL",
    long_name = "Symbol",
    description = "Engineering symbol with inline formatting",
    aliases = { "sym" },
    inline_prefix = "symbol",
}

M.handler = {
    name = "symbol_handler",
    on_render_Code = function(code, _ctx)
        local content = (code.text or ""):match("^symbol:%s*(.+)$")
            or (code.text or ""):match("^sym:%s*(.+)$")
        if not content then return nil end
        return { pandoc.Emph({ pandoc.Str(content) }) }
    end,
}

return M
```

Usage: `The force is defined as` `` `symbol: F = ma` ``.

Views that build their content from the database (ToC, lists of figures, abbreviation lists, traceability matrices) typically use `on_render_Code` and call shared helpers such as `ooxml_builder` or `list_table_helpers`.

### Float type

Floats are purely declarative — most don't need `M.handler`.

```src.lua:src-model-template-float{caption="types/floats/sequence_diagram.lua"}
local M = {}

M.float = {
    id = "SEQUENCE",
    long_name = "Sequence Diagram",
    caption_format = "Figure",
    counter_group = "FIGURE",      -- Shares numbering with FIGURE, PLANTUML, CHART
    aliases = { "seq", "sequence" },
}

return M
```

Usage:

````src.markdown:src-model-template-float-usage{caption="Authoring a float"}
```seq:auth-flow{caption="User authentication flow"}
sequence diagram content here
```
````

For floats that need an external tool (PlantUML, charts), see [External renderers](#external-renderers).

### Specification type

Specification types define the top-level document kinds (SRS, SDD, STD, …).

```src.lua:src-model-template-spec{caption="types/specifications/srs.lua"}
local M = {}

M.specification = {
    id = "SRS",
    long_name = "Software Requirements Specification",
    description = "MIL-STD-498 SRS document",
    is_default = false,
    implicit_aliases = { "Software Requirements Specification", "SRS" },
}

return M
```

Usage: `# srs: My Project Requirements @SRS-MYPROJ-001` at the top of a `.md` file.

## Schema field reference

### Object schema

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
  - Unique identifier (uppercase convention).
* - `long_name`
  - string
  - same as `id`
  - Human-readable name.
* - `description`
  - string
  - `""`
  - Description text.
* - `extends`
  - string
  - nil
  - Base type for attribute inheritance.
* - `is_default`
  - boolean
  - false
  - Headers without an explicit type match this.
* - `is_composite`
  - boolean
  - false
  - Hierarchical object (contains children with their own PIDs).
* - `pid_prefix`
  - string
  - nil
  - Prefix for auto-generated PIDs.
* - `pid_format`
  - string
  - nil
  - Printf format (e.g. `"%s-%03d"`).
* - `aliases`
  - list
  - nil
  - Alternative identifiers for syntax matching.
* - `implicit_aliases`
  - list
  - nil
  - Titles that auto-resolve to this type (e.g. `"Introduction"` -> `INTRODUCTION`).
* - `attributes`
  - list
  - nil
  - Attribute definitions (see below).
```

### Attribute definitions

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
  - Attribute identifier.
* - `type`
  - string
  - `"STRING"`
  - One of: `STRING`, `INTEGER`, `REAL`, `BOOLEAN`, `DATE`, `ENUM`, `XHTML`.
* - `min_occurs`
  - integer
  - 0
  - 0 = optional, 1 = required.
* - `max_occurs`
  - integer
  - 1
  - Maximum values.
* - `min_value` / `max_value`
  - number
  - nil
  - Bounds for numeric types.
* - `values`
  - list
  - nil
  - Required when `type = "ENUM"`.
* - `datatype_ref`
  - string
  - auto
  - Override the auto-generated datatype id. For ENUM types the default is `<TYPE_ID>_<attr_name>`.
```

### Float schema

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
  - Unique identifier.
* - `caption_format`
  - string
  - same as `id`
  - Prefix used in output captions (e.g. `"Figure"`).
* - `counter_group`
  - string
  - same as `id`
  - Counter sharing group. Floats with the same `counter_group` share a single numbering sequence.
* - `aliases`
  - list
  - nil
  - Alternative fence prefixes.
* - `needs_external_render`
  - boolean
  - false
  - See [External renderers](#external-renderers).
```

### Relation schema

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
  - Unique identifier.
* - `extends`
  - string
  - nil
  - Base relation type. Typically `PID_REF` (`@`) or `LABEL_REF` (`#`). Inherits selector, resolver, and default `on_render_Link`.
* - `link_selector`
  - string
  - inherited
  - Override the inherited selector. Rarely needed.
* - `source_type_ref`
  - string
  - nil
  - Constrain the source object type (nil = any).
* - `target_type_ref`
  - string
  - nil
  - Constrain the target type (nil = any). Comma-separated list accepted.
* - `source_attribute`
  - string
  - nil
  - Constrain to links inside this attribute.
* - `is_structural`
  - boolean
  - false
  - Derive from containment hierarchy instead of an explicit link.
```

### Inference scoring

When more than one relation type matches a link, the resolver scores each candidate (`+1` for each constraint that matches, eliminated on mismatch, `+0` on `nil`). The highest scorer wins; ties are flagged as `ambiguous_relation`. A link `[fig:diagram](#)` resolving against a FIGURE will match `XREF_FIGURE` (selector `#` + target_type_ref `FIGURE` = 2) over the generic `LABEL_REF` (selector `#` only = 1).

### View schema

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
  - Unique identifier.
* - `inline_prefix`
  - string
  - nil
  - Prefix for inline code dispatch (`"symbol"` enables `` `symbol: ...` ``).
* - `aliases`
  - list
  - nil
  - Alternative prefixes for the same view type.
* - `materializer_type`
  - string
  - nil
  - Strategy (`'toc'`, `'lof'`, `'custom'`) for built-in materialised views.
* - `counter_group`
  - string
  - nil
  - Counter group for numbered views.
* - `needs_external_render`
  - boolean
  - false
  - See [External renderers](#external-renderers).
```

## Extension checklist

1. Pick a model name (lowercase, matches the directory name).
2. Create `models/<name>/types/…` with the categories you need.
3. Declare the schema (`M.object` / `M.float` / …).
4. Add `M.handler` only if you need custom behaviour.
5. Set `template: <name>` in `project.yaml`.
6. Run `specc build` and inspect the output.
7. Add a verification view if the domain has rules to enforce (see [Verification views](#verification-views)).

## Verification views

Verification views are SQL-based validation rules that run during the VERIFY phase. Each verification view creates a SQL view; rows returned by the view are diagnostics.

Place verification view files under `models/<name>/verification_views/`. The loader scans that directory automatically — file names don't need a particular convention, but matching the `policy_key` helps (e.g. `sd_601_vc_missing_hlr.lua`).

```src.lua:src-model-verification-view{caption="models/mymodel/verification_views/vc_missing_hlr.lua"}
local M = {}

M.verification_view = {
    view = "view_traceability_vc_missing_hlr",
    policy_key = "traceability_vc_to_hlr",
    sql = [[
CREATE VIEW IF NOT EXISTS view_traceability_vc_missing_hlr AS
SELECT vc.identifier AS object_id, vc.pid AS object_pid,
       vc.title_text AS object_title, vc.from_file, vc.start_line
FROM spec_objects vc
WHERE vc.type_ref = 'VC'
  AND NOT EXISTS (
      SELECT 1 FROM spec_relations r
      JOIN spec_objects target ON target.identifier = r.target_ref
      WHERE r.source_ref = vc.identifier AND target.type_ref = 'HLR'
  );
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Verification case '%s' has no traceability link to an HLR", label)
    end,
}

return M
```

Suppress a verification view in `project.yaml` via its `policy_key`:

```src.yaml:src-model-suppress-verification-view{caption="Suppressing a verification view"}
validation:
  traceability_vc_to_hlr: ignore
```

## External renderers

Float and view types that need an external tool (PlantUML, ECharts, Graphviz, …) declare `needs_external_render = true` and register callbacks with `external_render.register_renderer` at module load time. The pipeline collects all such items, spawns the processes in parallel, and dispatches results back to each type.

Do **not** also define `M.handler.on_transform` for these types — the external render handler owns TRANSFORM for them.

```src.lua:src-model-external-render{caption="External renderer skeleton"}
local float_base     = require("pipeline.shared.float_base")
local task_runner    = require("infra.process.task_runner")
local external_render = require("pipeline.transform.external_render_handler")

local M = {}

M.float = {
    id = "PLANTUML",
    long_name = "PlantUML Diagram",
    caption_format = "Figure",
    counter_group = "FIGURE",
    aliases = { "puml", "plantuml" },
    needs_external_render = true,
}

external_render.register_renderer("PLANTUML", {
    prepare_task = function(float, build_dir, log)
        local content = float.raw_content or ""
        local hash = pandoc.sha1(content)
        local diagrams_path = build_dir .. "/diagrams"
        local puml_file = diagrams_path .. "/" .. hash .. ".puml"
        local png_file  = diagrams_path .. "/" .. hash .. ".png"

        task_runner.ensure_dir(diagrams_path)
        task_runner.write_file(puml_file, content)

        return {
            cmd = "plantuml",
            args = { "-tpng", puml_file },
            opts = { timeout = 30000 },
            output_path = png_file,   -- Cache key: skipped when the file exists.
            context = { hash = hash, float = float,
                        relative_path = "diagrams/" .. hash .. ".png" },
        }
    end,

    handle_result = function(task, success, _stdout, stderr, data, log)
        local ctx = task.context
        if not success then
            log.warn("PlantUML failed for %s: %s",
                ctx.float.identifier:sub(1,12), stderr)
            return
        end
        local json = string.format('{"png_paths":["%s"]}', ctx.relative_path)
        float_base.update_resolved_ast(data, ctx.float.identifier, json)
    end,
})

return M
```

```list-table:tbl-model-task-descriptor{caption="Task descriptor returned by prepare_task"}
> header-rows: 1
> aligns: l,l

* - Field
  - Purpose
* - `cmd`, `args`, `opts`
  - Process to spawn and its timeout/cwd. `opts.timeout` is in milliseconds.
* - `output_path`
  - File-based cache key. If the file exists on disk, `prepare_task` is not spawned — `handle_result` is called immediately with the cached path. Use the content hash in the filename so input changes trigger a fresh render.
* - `context`
  - Arbitrary table passed through to `handle_result`.
```

The same mechanism works for **views** — `math_inline` uses it to convert AsciiMath to OMML. The render handler queries `spec_views` (instead of `spec_floats`) for view-typed items.

## Project integration

```src.yaml:src-model-project-yaml{caption="Using a custom model in project.yaml"}
project:
  code: MYPROJ
  name: My Project

template: mymodel   # Loads models/default/ then models/mymodel/

doc_files:
  - srs.md
```

## Troubleshooting

**My type doesn't load.** Check that the file is under `types/<category>/<name>.lua`, that the category is one of `{objects, floats, views, relations, specifications}`, and that the module returns `M`. Non-view categories fail loudly; view load failures become warnings on stderr — watch the build output.

**My override isn't taking effect.** Overrides replace by `id`, not by filename. The custom type must declare the **same `id`** as the default (case-sensitive). Filename is irrelevant.

**My handler never fires.** If it's a decorated callback, make sure the dispatching phase is actually reached for your content kind (e.g. `on_render_SpecObject` only fires for objects that have a handler registered *and* pass the render handler's filter). If it's a phase hook, check its `prerequisites` — it won't run before its dependencies and an unresolvable dependency silently drops it from that phase.

**Handler name collision.** Every handler name is global. Use a unique prefix (`mymodel_hlr_handler`) when you're extending an overlay that might already define `hlr_handler`.

**My external renderer runs every build even without changes.** Your `output_path` isn't content-addressed. Include the content hash in the filename so unchanged input hits the file-based cache.

## Pointers

- [User manual](../manual.md) — day-to-day authoring syntax.
- Engineering docs — [type discovery](../../engineering_docs/architecture/type_discovery_design.md), [model design](../../engineering_docs/architecture/model_design.md) — for internals.
- [Concepts dictionary](../../engineering_docs/dictionary/concepts.md) — vocabulary reference.
