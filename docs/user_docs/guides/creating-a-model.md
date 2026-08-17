# Guide: Creating a Custom Model

## Introduction

A **model** defines the vocabulary and behavior of specification documents. It declares object types, floats, relations, views, and verification rules.

The `default` model provides base types such as `SECTION`, `FIGURE`, `TABLE`, and `PLANTUML`. A custom model can add or replace types. SpecCompiler loads the custom model as an overlay on `default`.

Each extension module returns one Lua descriptor table. The descriptor contains a `kind`, a `schema`, and an optional `hooks` table. The host registers the schema and indexes the hooks. The value of `schema.id` identifies the type.

Create a type as follows:

1. Decide the **kind** (`object`, `float`, `view`, `relation`, `specification`, or `analyze`).
2. Define the type in **`schema`**. The `schema.id` field is the authoritative identifier.
3. Add a **hook** only when the type requires custom behavior. The hook name determines its context and return type.

Most object and float types contain only data. These types omit `hooks` and inherit the applicable behavior.

## Quick-start template

Each type module has the following structure:

```src.lua:src-model-quickstart{caption="The descriptor a type module returns, annotated"}
-- File: models/<your-model>/types/<category>/<type-name>.lua
-- The module returns one descriptor table.
return {
    -- kind: object | float | view | relation | specification | analyze.
    -- It must match the category directory the file lives in.
    kind = "object",

    -- schema contains data. schema.id is authoritative.
    -- These fields become columns in the SpecIR database.
    schema = {
        id = "...",            -- required, uppercase convention, globally unique
        -- extends = "...",    -- inherit attributes + hooks from a base type
        -- attributes = { ... },
    },

    -- hooks contains optional custom behavior.
    -- The host classifies each hook by NAME, infers the role from the hooks
    -- present, and rejects a function placed on any other top-level key. A
    -- pure-data type (most objects/floats) omits this key entirely and
    -- inherits the host default.
    -- hooks = {
    --     render = function(ctx) ... end,   -- one hook whose name fits the intent
    -- },
}
```

Set `template: <your-model>` in `project.yaml`. The build then loads the model as an overlay on `default`.

## Worked example: a one-file, project-local model

A project-local model can contain one descriptor. The loader first searches `SPECCOMPILER_HOME/models/<name>/`. It then searches the project working directory.

The following model defines architecture decisions as traceable objects:

```src:src-model-adr-layout{caption="Project layout with a local model"}
my-project/
  project.yaml            -- template: adr
  decisions.md
  models/
    adr/
      types/
        objects/
          decision.lua    -- the whole model
```

```src.lua:src-model-adr-descriptor{caption="models/adr/types/objects/decision.lua — the complete model"}
return {
    kind = "object",
    schema = {
        id = "DECISION",
        long_name = "Architecture Decision",
        extends = "SECTION",
        pid_prefix = "ADR",
        pid_format = "%s-%03d",
        attributes = {
            { name = "status", type = "ENUM",
              values = { "Proposed", "Accepted", "Superseded" } },
            { name = "consequences", type = "XHTML" },
        },
    },
}
```

No `hooks` key: rendering, PID assignment, labels, and cross-reference resolution are all inherited. Set `template: adr` in `project.yaml` and author decisions like any other typed object:

```src.markdown:src-model-adr-usage{caption="decisions.md"}
# Architecture Decisions @SPEC-ADR-001

## DECISION: Use SQLite for the IR @ADR-001

> status: Accepted

> consequences: The build produces one file. SQL queries provide traceability data.

We store the intermediate representation in a SQLite database rather than
in-memory tables, so analyze queries can use SQL.

## DECISION: Run on stock pandoc

> status: Proposed

Use the system Pandoc with Lua and C extensions.
```

The build registers `DECISION` and assigns the second decision the PID `ADR-002`. It stores the attributes for queries. It also resolves `[ADR-001](@)` references. The type requires no custom behavior.

## Overlay

Models layer as **overlays** on top of `default`. When `project.yaml` sets `template: mymodel`, the loader runs two passes:

1. `models/default/types/` — loaded first.
2. `models/mymodel/types/` — loaded second. A descriptor with the same kind and `schema.id` replaces the default descriptor.

Descriptors with new identifiers supplement the default descriptors. The model inherits definitions that it does not replace.

## Model directory layout

```src:src-model-directory-layout{caption="Model directory structure"}
models/<your-model>/
  types/
    objects/          -- Object types        (e.g., hlr.lua, vc.lua)
    specifications/   -- Specification types (e.g., srs.lua)
    floats/           -- Float types         (e.g., sequence_diagram.lua)
    views/            -- View types          (e.g., symbol.lua)
    relations/        -- Relation types      (e.g., traces_to.lua)
  analyze_queries/     -- Analyze descriptors (e.g., vc_missing_hlr.lua)
  postprocessors/     -- Per-format post-processing (docx.lua, html5.lua)
  filters/            -- Pandoc Lua filters per output format
  styles/             -- Style presets (preset.lua, docx.lua, html.lua)
  model.yaml          -- Optional manifest: name, description, requires
```

Only `types/` is required. All other directories are optional.

A model that depends on another model declares it in `model.yaml`:

```src.yaml:src-model-manifest{caption="model.yaml — declaring a model dependency"}
name: mymodel
description: My domain model
requires: [base_model]   # Load this model first.
```

The engine loads each model in `requires` before it loads the requesting model. It loads each dependency once. A missing dependency stops the build. A model can contain external tools in `tools/`. The five `types/` directory names are fixed. Each directory maps to one descriptor kind. A mismatch between the directory and `kind` stops the build.

The loader supports single files such as `types/floats/figure.lua`. It also supports directories with an `init.lua` file.

## Type categories

```list-table:tbl-model-categories{caption="Type categories, their kind, and the hooks they typically declare"}
> header-rows: 1
> aligns: l,l,l,l

* - Category
  - `kind`
  - Example file
  - Hooks typically declared
* - Object
  - `"object"`
  - `types/objects/hlr.lua`
  - none (omit `hooks`), or `render`
* - Float
  - `"float"`
  - `types/floats/figure.lua`
  - `transform`, or `prepare_task` + `handle_result`
* - Relation
  - `"relation"`
  - `types/relations/traces_to.lua`
  - none, `render_link`, or `resolve`
* - View
  - `"view"`
  - `types/views/abbrev.lua`
  - `render`, `render_block`, `dataset`, `build_block`
* - Specification
  - `"specification"`
  - `types/specifications/srs.lua`
  - none (omit `hooks`)
* - Analyze query
  - `"analyze"`
  - `analyze_queries/vc_missing_hlr.lua`
  - `message`
```

## The descriptor and hook contract

The `hooks` table contains all custom type behavior. Each hook accepts one frozen context table. The polymorphic `ctx.subject` field contains the hook input. The `ctx.capability` field identifies the hook. Use `ctx:require("field")` to require a non-nil field.

The hook name determines the context tier and return type. During model loading, the host validates each hook against the descriptor kind. An invalid hook stops the build.

**Render-tier hooks** run during EMIT. They receive the render context and a resolved payload in `ctx.subject`. They return Pandoc AST. Link hooks return display text.

**Data-tier hooks** run during a data or lifecycle phase. They receive a data context without a Pandoc element or output format. Each hook returns its documented value.

**The host enforces return types.** The host checks the value when it dispatches a hook. An invalid value stops the build and identifies the kind, type, and hook. A `nil` value selects inherited behavior. The analyze-query `message` hook must return a string.

**Phase hooks** participate in pipeline phases. Declare them as `on_<phase>` functions in `hooks`. Each phase hook runs once per phase with `(data, contexts, diagnostics)`. Use `schema.phase_prerequisites` to declare ordering constraints. The host names the handler `<lowercase id>_handler`.

```list-table:tbl-model-hook-catalogue{caption="The hook catalogue: each hook's kind, tier, the one return type, and when it fires"}
> header-rows: 1
> aligns: l,l,l,l,l

* - Hook
  - Kind(s)
  - Tier
  - Returns
  - When it fires
* - `render`
  - object, specification, float, view
  - render
  - Pandoc Block(s) / Inlines
  - EMIT, when the element of this type is being rendered.
* - `render_block`
  - view
  - render
  - Pandoc Block
  - EMIT, for a block view written as a fenced ```` ```prefix ```` code block.
* - `render_link`
  - relation
  - render
  - display string (or `nil`)
  - EMIT, to produce the visible text of a link of this relation type.
* - `message`
  - analyze
  - render
  - diagnostic string
  - ANALYZE, once per row the SQL view returns.
* - `dataset`
  - view
  - data
  - `{ source | data | links }`
  - When a chart/data view needs its dataset (`ctx.subject.params`).
* - `build_block`
  - view
  - data
  - Pandoc Block
  - When a `TABLE_VIEW` subtype builds its generated table.
* - `transform`
  - float
  - data
  - resolved-AST string
  - TRANSFORM, to resolve a float internally (`ctx.subject.raw_content`, `.float`).
* - `prepare_task`
  - float
  - data
  - task table (or `nil` to skip)
  - TRANSFORM, to spawn an external tool (`ctx.subject.float`, `.build_dir`).
* - `handle_result`
  - float
  - data
  - (writes resolved AST)
  - After the external tool finishes (`ctx.subject.task`, `.success`, `.stderr`).
* - `resolve`
  - relation
  - data
  - `{ target, ambiguous }`
  - ANALYZE, to resolve a link of this relation type (`ctx.subject.target_text`).
```

A float is internal **or** external: declaring `render` together with `prepare_task`/`handle_result` is a contradiction and the host rejects it.

**Context fields**

```list-table:tbl-model-ctx-fields{caption="The frozen context fields, by tier"}
> header-rows: 1
> aligns: l,l

* - Field
  - Meaning
* - `ctx.subject`
  - The hook-specific payload. Examples include an object, float, view parameters, relation target, or analyze-query row.
* - `ctx.data`
  - The `DataManager` (the SpecIR database) for custom queries. Present on both tiers.
* - `ctx.spec_id`
  - Identifier of the specification being processed. Present on both tiers.
* - `ctx.log`
  - Logger (`log.warn`, `log.debug`, …). Present on both tiers.
* - `ctx.pandoc`
  - The Pandoc module. **Render tier only** — a data hook has no Pandoc element yet.
* - `ctx.format`
  - Target output format (`docx`, `html5`, `gfm`, `json`). **Render tier only.**
* - `ctx.diagnostics`, `ctx.model`, `ctx.config`
  - Diagnostics sink, model name, and project config. These fields are always in the render tier. A data context contains them when available.
* - `ctx.host`
  - The registry, for cross-hook dispatch (e.g. `ctx.host:get_hook("view", id, "build_block")`). Render tier.
```

> Read the resolved element and its attributes from `ctx.subject`. Query the database only for data that the subject does not contain.

## Five canonical templates

### Object type

Create an object type with required attributes and a custom render. The render hook reads its element and attributes from `ctx.subject`:

```src.lua:src-model-template-object{caption="types/objects/hlr.lua"}
local render_utils = require("pipeline.shared.render_utils")

return {
    kind = "object",
    schema = {
        id = "HLR",
        long_name = "High-Level Requirement",
        description = "A top-level system requirement",
        extends = "TRACEABLE",       -- inherit the standard traceable card
        pid_prefix = "HLR",
        pid_format = "%s-%03d",
        attributes = {
            { name = "priority", type = "ENUM",
              values = { "High", "Medium", "Low" },
              min_occurs = 1, max_occurs = 1 },
            { name = "rationale", type = "XHTML" },
        },
    },
    hooks = {
        -- EMIT: ctx.subject carries { object, attributes, element, ... } already
        -- resolved by the pipeline, so no DB query is needed for our own item.
        render = function(ctx)
            local obj   = ctx.subject.object
            local attrs = ctx.subject.attributes or {}
            local priority = (attrs.priority or {}).value or "?"

            local blocks = {}
            local level = math.max((ctx.subject.header_level or 2) - 1, 1)
            local hdr = ctx.pandoc.Header(level,
                { ctx.pandoc.Str(obj.pid .. ": " .. (obj.title_text or "")) })
            render_utils.add_header_blocks(blocks, hdr)
            table.insert(blocks, ctx.pandoc.Para({
                ctx.pandoc.Strong({ ctx.pandoc.Str("Priority: ") }),
                ctx.pandoc.Str(priority),
            }))
            return blocks
        end,
    },
}
```

Usage:

```src.markdown:src-model-template-object-usage{caption="Authoring an HLR in Markdown"}
## HLR: User Authentication @HLR-001

> priority: High
> rationale: Required by security policy section 4.2

The system shall authenticate users via username and password.
```

Most object types do not require a `render` hook. Without this hook, the host emits the standard PID, attributes, and body. Add `render` only for a different layout.

### Relation type

The common case is a simple subtype that narrows a base relation (`PID_REF` for `@` or `LABEL_REF` for `#`). No hooks needed — `extends` inherits the selector, resolver, and default link display:

```src.lua:src-model-template-relation-simple{caption="types/relations/traces_to.lua"}
return {
    kind = "relation",
    schema = {
        id = "TRACES_TO",
        extends = "PID_REF",
        long_name = "Traces To",
        description = "Traceability link from one object to another",
        source_type_ref = "LLR",
        target_type_ref = "HLR",
    },
}
```

The link `[HLR-001](@)` inside an LLR resolves as `TRACES_TO`.

When the default display text (PID for objects, `"<caption> <number>"` for floats) isn't right, add a `render_link` hook. It reads the pre-resolved target from `ctx.subject.target` and returns the display string (or `nil` to fall back to the base type):

```src.lua:src-model-template-relation-display{caption="Custom display text via a render_link hook"}
hooks = {
    -- Render section refs as "<hierarchical-number> <title>", e.g. "3.4 Introduction".
    render_link = function(ctx)
        local target = ctx.subject.target
        local title  = target.title or ""
        local number = target.pid and target.pid:match("sec([%d%.]+)$")
        if number and title ~= "" then return number .. " " .. title end
        if title ~= "" then return title end
        return target.pid
    end,
}
```

`ctx.subject.target` contains the resolved target. Object targets contain the kind, PID, title, and type. Float targets contain the kind, caption, and number. Return a string to replace the display text. Return `nil` to use inherited behavior. `LABEL_REF` and `PID_REF` provide default link rendering.

For custom relation resolution, declare a `resolve` data hook. It reads the target text and source identifier from `ctx.subject`. It returns `{ target, ambiguous }`. Subtypes of `PID_REF` and `LABEL_REF` inherit their resolvers.

### Walkthrough custom view

Backtick syntax invokes views. An **inline** view uses `render` and returns inlines. A **block** view uses `render_block` and returns a block. The `inline_prefix` and `aliases` fields select the view.

```src.lua:src-model-template-view{caption="types/views/symbol.lua"}
return {
    kind = "view",
    schema = {
        id = "SYMBOL",
        long_name = "Symbol",
        description = "Engineering symbol with inline formatting",
        aliases = { "sym" },
        inline_prefix = "symbol",
    },
    hooks = {
        -- EMIT: ctx.subject.element is the Pandoc Code element.
        render = function(ctx)
            local text = ctx.subject.element.text or ""
            local content = text:match("^symbol:%s*(.+)$") or text:match("^sym:%s*(.+)$")
            if not content then return nil end
            return { ctx.pandoc.Emph({ ctx.pandoc.Str(content) }) }
        end,
    },
}
```

Usage: `The force is defined as` `` `symbol: F = ma` ``.

Database-backed views usually render a **block**. Extend `TABLE_VIEW` and declare a `build_block` data hook. The inherited `render_block` hook dispatches `build_block`. A `TABLE_VIEW` subtype without `build_block` causes a load error.

```src.lua:src-model-template-view-block{caption="A generated table view via build_block (types/views/traceability_matrix.lua)"}
return {
    kind = "view",
    schema = {
        id = "TRACEABILITY_MATRIX",
        extends = "TABLE_VIEW",          -- inherits the shared render_block
        long_name = "Traceability Matrix",
        description = "HLR to VC traceability with test results",
        inline_prefix = "traceability_matrix",
    },
    hooks = {
        -- DATA: build the generated table. dctx.data is the SpecIR database.
        -- dctx.subject.params holds any view parameters.
        build_block = function(dctx)
            local rows = dctx.data:query_all([[
                SELECT hlr.pid AS hlr_pid, vc.pid AS vc_pid
                FROM spec_relations r
                JOIN spec_objects vc  ON r.source_object_id = vc.id
                JOIN spec_objects hlr ON r.target_object_id = hlr.id
                WHERE vc.type_ref = 'VC' AND hlr.type_ref = 'HLR'
                  AND vc.specification_ref = :spec_id
                ORDER BY hlr.pid, vc.pid
            ]], { spec_id = dctx.spec_id })
            if not rows or #rows == 0 then
                return pandoc.Para({ pandoc.Str("No HLR-VC traceability found.") })
            end
            local header = {
                { pandoc.Plain({ pandoc.Strong({ pandoc.Str("HLR") }) }) },
                { pandoc.Plain({ pandoc.Strong({ pandoc.Str("VC")  }) }) },
            }
            local body = {}
            for _, row in ipairs(rows) do
                table.insert(body, {
                    { pandoc.Plain({ pandoc.Str(row.hlr_pid or "") }) },
                    { pandoc.Plain({ pandoc.Str(row.vc_pid  or "") }) },
                })
            end
            local tbl = pandoc.SimpleTable({}, { pandoc.AlignLeft, pandoc.AlignLeft },
                { 0, 0 }, header, body)
            return pandoc.utils.from_simple_table(tbl)
        end,
    },
}
```

A view that supplies chart data declares a `dataset` hook. The hook returns `{ source = ... }` or the data shape required by the chart type.

### Walkthrough custom float type

Most floats require only a `schema`:

```src.lua:src-model-template-float{caption="types/floats/sequence_diagram.lua"}
return {
    kind = "float",
    schema = {
        id = "SEQUENCE",
        long_name = "Sequence Diagram",
        caption_format = "Figure",
        counter_group = "FIGURE",      -- shares numbering with FIGURE, PLANTUML, CHART
        aliases = { "seq", "sequence" },
    },
}
```

Usage:

````src.markdown:src-model-template-float-usage{caption="Authoring a float"}
```seq:auth-flow{caption="User authentication flow"}
sequence diagram content here
```
````

An internally rendered float can declare a `transform` data hook. The hook reads `ctx.subject.raw_content` and `ctx.subject.float`. It returns a resolved-AST string. See [External renderers](#external-renderers) for process-based rendering.

### Specification type

Specification types define the top-level document kinds (SRS, SDD, STD, …). They are pure-data — no `hooks` at all:

```src.lua:src-model-template-spec{caption="types/specifications/srs.lua"}
return {
    kind = "specification",
    schema = {
        id = "SRS",
        long_name = "Software Requirements Specification",
        description = "MIL-STD-498 SRS document",
        is_default = false,
        implicit_aliases = { "Software Requirements Specification", "SRS" },
        attributes = {
            { name = "version", type = "STRING" },
            { name = "date",    type = "STRING" },
        },
    },
}
```

Usage: `# srs: My Project Requirements @SRS-MYPROJ-001` at the top of a `.md` file.

## Schema field reference

The following tables define common schema fields. Some model hooks also read additional schema fields for rendering.

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
  - Base type for attribute + hook inheritance (e.g. `TRACEABLE`).
* - `is_default`
  - boolean
  - false
  - Headers without an explicit type match this type.
* - `is_composite`
  - boolean
  - false
  - Hierarchical object (contains children with their own PIDs).
* - `is_required`
  - boolean
  - false
  - The specification must contain at least one object of this type.
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
  - Titles that auto-resolve to this type (e.g. `"References"` -> `REFERENCES`).
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
  - One of: `STRING`, `INTEGER` (`INT` accepted), `REAL`, `BOOLEAN`, `DATE`, `ENUM`, `XHTML`.
* - `min_occurs`
  - integer
  - 0
  - 0 = optional, 1 = required.
* - `max_occurs`
  - integer
  - 1
  - Maximum number of values.
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
  - Override the auto-generated datatype id. For `ENUM` the default is `<TYPE_ID>_<attr_name>`.
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
* - `long_name`
  - string
  - same as `id`
  - Human-readable name.
* - `description`
  - string
  - `""`
  - Description text.
* - `caption_format`
  - string
  - same as `id`
  - Prefix used in output captions (e.g. `"Figure"`).
* - `counter_group`
  - string
  - same as `id`
  - Counter sharing group. Floats with the same `counter_group` share one numbering sequence.
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
  - Base relation type. Typically `PID_REF` (`@`) or `LABEL_REF` (`#`). Inherits selector, `resolve`, and default `render_link`.
* - `link_selector`
  - string
  - inherited
  - Override the inherited selector (`@` or `#`). Rarely needed.
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
  - Derive from the containment hierarchy instead of an explicit link.
```

### Inference scoring

When multiple relation types match a link, the resolver scores each candidate. A matching constraint adds one point. A mismatch removes the candidate. A `nil` constraint adds no points. The highest score wins. A tie produces an `ambiguous_relation` diagnostic.

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
* - `long_name`
  - string
  - same as `id`
  - Human-readable name.
* - `inline_prefix`
  - string
  - nil
  - Prefix for inline-code dispatch (`"symbol"` enables `` `symbol: ...` ``).
* - `aliases`
  - list
  - nil
  - Alternative prefixes for the same view type.
* - `materializer_type`
  - string
  - nil
  - Strategy (`'toc'`, `'lof'`, …) for built-in materialised views.
* - `counter_group`
  - string
  - nil
  - Counter group for numbered views.
* - `view_subtype_ref`
  - string
  - nil
  - The view-element subtype this view aggregates (e.g. `ABBREV`).
* - `needs_external_render`
  - boolean
  - false
  - See [External renderers](#external-renderers).
```

## Extension checklist

1. Pick a model name (lowercase, matches the directory name).
2. Create `models/<name>/types/…` with the categories you need.
3. Return one descriptor with `kind`, `schema`, and optional `hooks` fields.
4. Add only the hooks that implement required custom behavior.
5. Set `template: <name>` in `project.yaml`.
6. Run `specc build` and inspect the output.
7. Add an analyze descriptor if the domain has rules to enforce.

## Analyze queries

Analyze queries are SQL-based validation rules that run during ANALYZE. Each query uses a descriptor with `kind = "analyze"`. Its schema defines a SQL view. Its optional `message` hook converts a result row into a diagnostic.

Place analyze descriptors under `models/<name>/analyze_queries/`. The loader scans all Lua files in this directory. Use the policy key as the file name when practical.

```src.lua:src-model-verification-view{caption="models/mymodel/analyze_queries/vc_missing_hlr.lua"}
return {
    kind = "analyze",
    schema = {
        id = "vc_missing_hlr",
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
    },
    hooks = {
        -- ANALYZE: one call per row. ctx.subject.row contains the query result.
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "Verification case '%s' has no traceability link to an HLR", label)
        end,
    },
}
```

The `policy_key` controls diagnostic severity. An overlay descriptor with the same key replaces the earlier descriptor. A schema with `disabled = true` removes the key. Set a policy to `ignore` in `project.yaml` to suppress its diagnostics:

```src.yaml:src-model-suppress-verification-view{caption="Suppressing an analyze query"}
validation:
  traceability_vc_to_hlr: ignore
```

## External renderers

Floats that require an external tool set `needs_external_render = true`. They declare `prepare_task` and `handle_result` data hooks. The pipeline collects tasks, runs processes, and dispatches each result.

The `prepare_task` hook returns a task descriptor. The `handle_result` hook stores the resolved result. A float cannot declare `render` with either external-render hook.

```src.lua:src-model-external-render{caption="types/floats/plantuml.lua — an external-render float"}
local float_base  = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")

return {
    kind = "float",
    schema = {
        id = "PLANTUML",
        long_name = "PlantUML Diagram",
        caption_format = "Figure",
        counter_group = "FIGURE",
        aliases = { "puml", "plantuml" },
        needs_external_render = true,
    },
    hooks = {
        -- DATA: build the spawn task. dctx.subject contains { float, build_dir }.
        -- dctx.log is the logger. Return the task descriptor, or nil to skip.
        prepare_task = function(dctx)
            local float     = dctx.subject.float
            local build_dir = dctx.subject.build_dir
            local content   = float.raw_content or ""
            local hash      = pandoc.sha1(content)
            local diagrams  = build_dir .. "/diagrams"
            local puml_file = diagrams .. "/" .. hash .. ".puml"
            local png_file  = diagrams .. "/" .. hash .. ".png"

            task_runner.ensure_dir(diagrams)
            task_runner.write_file(puml_file, content)

            return {
                cmd = "plantuml",
                args = { "-tpng", puml_file },
                opts = { timeout = 30000 },
                output_path = png_file,   -- cache key: skipped when the file exists
                context = { float = float, relative_path = "diagrams/" .. hash .. ".png" },
            }
        end,

        -- DATA: write the resolved AST. dctx.subject carries
        -- { task, success, stdout, stderr }. dctx.data is the SpecIR database.
        handle_result = function(dctx)
            local task = dctx.subject.task
            local ctx  = task.context
            if not dctx.subject.success then
                dctx.log.warn("PlantUML failed: %s", dctx.subject.stderr)
                return
            end
            local json = string.format('{"png_paths":["%s"]}', ctx.relative_path)
            float_base.update_resolved_ast(dctx.data, ctx.float.id, json)
        end,
    },
}
```

```list-table:tbl-model-task-descriptor{caption="Task descriptor returned by prepare_task"}
> header-rows: 1
> aligns: l,l

* - Field
  - Purpose
* - `cmd`, `args`, `opts`
  - Process and options. `opts.timeout` is in milliseconds. `opts.cwd` sets the working directory.
* - `output_path`
  - File-based cache key. If the file already exists, the process is not spawned — `handle_result` runs immediately with the cached path. Put the content hash in the filename so input changes trigger a fresh render.
* - `context`
  - Arbitrary table passed through to `handle_result` (read as `task.context`).
```

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

**A type does not load.** Check the file location and returned descriptor. The kind must match its category directory. Type-load errors stop the build. View module load errors produce warnings.

**The host rejects a hook.** Check that the hook is valid for the descriptor kind. Put all custom behavior in `hooks`.

**An overlay does not replace a type.** Use the same case-sensitive `schema.id` and kind as the base descriptor.

**A render hook produces no output.** A `TABLE_VIEW` subtype must declare `build_block`. An object hook that returns `nil` retains the original element. Return the generated blocks to replace it.

**An external renderer runs for unchanged input.** Include the content hash in `output_path` to use the file cache.

## Pointers

- [User manual](../manual.md) — day-to-day authoring syntax.
- Engineering docs — the [type system SDD](../../engineering_docs/architecture/type_system.md) defines the contract. [Type discovery](../../engineering_docs/architecture/type_discovery_design.md) and [model design](../../engineering_docs/architecture/model_design.md) define internal behavior.
- [Concepts dictionary](../../engineering_docs/dictionary/concepts.md) — vocabulary reference.
