# Guide: Creating a Custom Model

## Introduction

A **model** is the vocabulary and behaviour of your specification documents. It declares what object types exist (requirements, design items, test cases), what floats are available (diagrams, tables, code listings), how cross-references resolve, and what validation rules run. When your domain needs a type the defaults don't cover, you write a model.

SpecCompiler ships with a `default` model that gives you the base types (`SECTION`, `FIGURE`, `TABLE`, `PLANTUML`, …). You create a custom model when your domain needs extra types, specialised rendering, or extra validation. Your model layers on top of `default`, so you only write the parts you want to change.

Here is the whole mental model in one breath: each extension point is **one Lua file that returns one descriptor table**. A descriptor has two required keys — a `kind` and a `schema` holding your data — plus an optional `hooks` table holding any behaviour. You pick the `kind`, put your data in `schema`, and (only when you need behaviour) pick the hook whose name matches what you want to do. The host engine reads that table, writes your type into the database, and indexes your hooks. That's it — there is no second registration step and no magic file naming.

The recipe never changes:

1. Decide the **kind** (`object`, `float`, `view`, `relation`, `specification`, or `verification`).
2. Put your data in **`schema`** (the authoritative `id`, `extends`, `attributes`, …).
3. Pick the **hook** whose name matches the intent — a `render`/`render_block`/`render_link` hook to produce output during EMIT, or a data hook like `dataset`, `transform`, or `resolve` to produce data earlier. The hook name decides both the context you receive and the type you must return.

A pure-data type — most objects and floats — simply omits `hooks` and inherits everything else.

## Quick-start template

Every type module has the same shape. Copy this skeleton and keep only what you need:

```src.lua:src-model-quickstart{caption="The descriptor a type module returns, annotated"}
-- File: models/<your-model>/types/<category>/<type-name>.lua
-- The module returns ONE descriptor table; the host reads only this table.
return {
    -- kind: object | float | view | relation | specification | verification.
    -- It must match the category directory the file lives in.
    kind = "object",

    -- schema: your DATA. schema.id is authoritative (NOT the filename).
    -- These fields become columns in the SpecIR database.
    schema = {
        id = "...",            -- required, uppercase convention, globally unique
        -- extends = "...",    -- inherit attributes + hooks from a base type
        -- attributes = { ... },
    },

    -- hooks (OPTIONAL): your BEHAVIOUR, and the ONLY place behaviour may live.
    -- The host classifies each hook by NAME, infers the role from the hooks
    -- present, and rejects a function placed on any other top-level key. A
    -- pure-data type (most objects/floats) omits this key entirely and
    -- inherits the host default.
    -- hooks = {
    --     render = function(ctx) ... end,   -- one hook whose name fits the intent
    -- },
}
```

Set `template: <your-model>` in `project.yaml` (see [Project Integration](#project-integration)) and `specc build` will load your types on top of `default`.

## Worked example: a one-file, project-local model

The smallest useful model is a single descriptor, and it can live **inside your project directory** — no need to touch the SpecCompiler installation. The loader resolves `models/<name>/` under `SPECCOMPILER_HOME` first, then under the project's working directory.

Suppose you want to record architecture decisions (ADRs) as first-class, traceable objects:

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

> consequences: Single-file build artifact; traceability is SQL-queryable.

We store the intermediate representation in a SQLite database rather than
in-memory tables, so verification views can run plain SQL.

## DECISION: Run on stock pandoc

> status: Proposed

No custom pandoc build; ship Lua + C extensions that load into the system
pandoc.
```

`specc build` registers `DECISION`, gives the second decision the auto-generated PID `ADR-002` (from `pid_prefix`/`pid_format`), stores `status` and `consequences` as queryable attributes, and resolves `[ADR-001](@)` cross-references from anywhere in the document — all without a single line of behaviour code.

## Overlay

Models layer as **overlays** on top of `default`. When `project.yaml` sets `template: mymodel`, the loader runs two passes:

1. `models/default/types/` — loaded first.
2. `models/mymodel/types/` — loaded second; a descriptor whose `schema.id` matches a default one replaces the default (the database insert is `INSERT OR REPLACE`, so the last writer per id wins).

Descriptors with new `id`s are added alongside the defaults. Everything you don't redefine is inherited.

## Model directory layout

```src:src-model-directory-layout{caption="Model directory structure"}
models/<your-model>/
  types/
    objects/          -- Object types        (e.g., hlr.lua, vc.lua)
    specifications/   -- Specification types (e.g., srs.lua)
    floats/           -- Float types         (e.g., sequence_diagram.lua)
    views/            -- View types          (e.g., symbol.lua)
    relations/        -- Relation types      (e.g., traces_to.lua)
  verification_views/ -- Verification descriptors (e.g., vc_missing_hlr.lua)
  postprocessors/     -- Per-format post-processing (docx.lua, html5.lua)
  filters/            -- Pandoc Lua filters per output format
  styles/             -- Style presets (preset.lua, docx.lua, html.lua)
  model.yaml          -- Optional manifest: name, description, requires
```

Only `types/` is required; everything else is optional.

A model that depends on another model declares it in `model.yaml`:

```src.yaml:src-model-manifest{caption="model.yaml — declaring a model dependency"}
name: mymodel
description: My domain model
requires: [base_model]   # loaded before this model; missing = loud load error
```

When the engine loads a model it first loads every model in `requires` (recursively, each at most once), erroring loudly if a required model is absent. A model can also carry its own external tooling under a `tools/` directory — the `abnt` model does exactly this for chart rendering: it owns the `CHART` float, the `gauss` dataset view, and the deno-based renderer at `models/abnt/tools/echarts-render.ts`, plus a `scripts/bootstrap.sh` to provision the deno dependency on native installs. The five `types/` subdirectory names are fixed — the loader maps each directory to a `kind` (`objects` -> `object`, `floats` -> `float`, and so on) and a descriptor's `kind` **must** match the directory it lives in, or load fails loudly.

The loader supports both single files (`types/floats/figure.lua`) and subdirectories with an `init.lua` (`types/floats/figure/init.lua`) — useful when a type needs helper modules alongside it.

## Type categories at a glance

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
* - Verification
  - `"verification"`
  - `verification_views/vc_missing_hlr.lua`
  - `message`
```

## The descriptor and hook contract

`hooks` is the single behaviour surface for every type. Every hook takes exactly **one** frozen context table as its sole argument. That context carries a polymorphic `ctx.subject` (the thing being acted on) and a `ctx.capability` (which hook this is). Use `ctx:require("field")` to fetch a field, erroring loudly if it is nil.

The hook **name** decides everything: which of the two context tiers you receive, and which single value you must return. The host validates the name against the kind at load time, so a misspelled or wrong-kind hook is a loud register-time error, not a silent no-op.

**Render-tier hooks** run during the EMIT walk, where a Pandoc element is being turned into output. They receive the render context (`data`, `pandoc`, `log`, `diagnostics`, `format`, `spec_id`, `model`, `config`, `host`) and `ctx.subject` holds the Pandoc element plus its resolved payload. They return Pandoc AST (or, for links, a display string).

**Data-tier hooks** run earlier, in a data or lifecycle phase (TRANSFORM / ANALYZE / external render). There is no Pandoc element and no chosen output format yet, so they receive the leaner data context (`data`, `spec_id`, `log`; `model`/`config`/`diagnostics`/`host` ride along when available). Each returns one documented value.

**Return types are enforced.** Every hook's contract declares what it must return — Pandoc AST (a table/element) or a string — and the host checks the value at dispatch time. A wrong-typed return fails loudly with the kind, type id, and hook name, instead of surfacing as a confusing pandoc error or silently missing output. Returning `nil` always means "nothing produced, fall back" (except the verification `message` hook, which must return a string).

**Phase hooks.** A type that needs to participate in a pipeline phase declares `on_<phase>` functions (`on_initialize`, `on_analyze`, `on_transform`, `on_verify`, `on_emit`) directly in `hooks`, beside its behaviour hooks. These run once per phase with the signature `(data, contexts, diagnostics)` — they are pipeline handlers, not per-element hooks. If the work must run after another handler, declare the ordering in the schema: `schema.phase_prerequisites = { "spec_views" }`. (The host registers the handler under the derived name `<lowercase id>_handler`.)

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
  - verification
  - render
  - diagnostic string
  - VERIFY, once per row the verification SQL view returns.
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

**What's on the context**

```list-table:tbl-model-ctx-fields{caption="The frozen context fields, by tier"}
> header-rows: 1
> aligns: l,l

* - Field
  - Meaning
* - `ctx.subject`
  - The polymorphic payload for this hook (e.g. `{ object, attributes, specification, element }` for an object render, `{ float, raw_content }` for a float transform, `{ params }` for a view dataset, `{ target }` for a link render, `{ row }` for a verification message). The shape depends on the hook.
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
  - Diagnostics sink, model name, project config. Always on the render tier; on the data tier when the caller has them.
* - `ctx.host`
  - The registry, for cross-hook dispatch (e.g. `ctx.host:get_hook("view", id, "build_block")`). Render tier.
```

> If you catch yourself starting a render hook with a DB query for "the thing I'm rendering", check `ctx.subject` first — the pipeline has already resolved the element and its attributes onto it, so you rarely need a query for your own item.

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

Most object types don't need a `render` hook at all — omit `hooks` and the host emits the standard PID-header / attributes / body card. Add a `render` hook only when the default layout isn't what you want.

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

That's complete. The link `[HLR-001](@)` written inside an LLR will resolve as `TRACES_TO`.

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

`ctx.subject.target` is pre-resolved. Object targets carry `{ kind = "object", pid, title, type_ref }`; float targets carry `{ kind = "float", caption, number, ... }`. Return a string to override the display text, or `nil` to let the base type's `render_link` take over. `LABEL_REF` and `PID_REF` each ship with a default `render_link` (title for sections, PID for other objects, `"<caption> <number>"` for floats), inherited automatically through `extends`, so you only write `render_link` when you want something different.

If a relation needs custom resolution (how the link text maps to a target object), declare a `resolve` data hook returning `{ target, ambiguous }`. It reads `ctx.subject.target_text` and `ctx.subject.source_object_id` from the leaner data context (`PID_REF` and `LABEL_REF` provide the standard ones, so subtypes almost never need their own).

### Walkthrough custom view

Views are written with backtick syntax. An **inline** view (`` `prefix: content` ``) uses a `render` hook returning inlines; a **block** view (a fenced ```` ```prefix ```` code block) uses a `render_block` hook returning a block. The view's `inline_prefix` (plus any `aliases`) is what routes the syntax to your hook.

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

Views that build their content from the database (lists of figures, abbreviation lists, traceability matrices) usually render a **block**. The cleanest way to do this is to extend `TABLE_VIEW` and declare only a `build_block` data hook — the shared `render_block` on `TABLE_VIEW` finds your `build_block` through the host and runs it. (The host enforces this: a view that extends `TABLE_VIEW` but provides no `build_block` is a load error.)

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
        -- DATA: build the generated table. dctx.data is the SpecIR database;
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

A view that feeds a chart (rather than emitting its own block) declares a `dataset` data hook instead, returning a `{ source = ... }` dataset that the chart consumes. The `gauss` view in the `abnt` model (its chart capability) is the canonical example.

### Walkthrough custom float type

Floats are usually purely declarative — most just need a `schema`:

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

A float that resolves its own content **internally** (no external tool) declares a single `transform` data hook. It reads `ctx.subject.raw_content` and `ctx.subject.float` and returns the resolved-AST string the backend consumes — the `FIGURE` type does exactly this to turn an image path into the JSON the image fallback renders. For floats that need an **external** tool (PlantUML, charts), see [External renderers](#external-renderers).

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

The fields below are the real `schema` keys the host writes into the SpecIR database (from `contract.registry`). Anything not listed is ignored by the insert.

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

When more than one relation type matches a link, the resolver scores each candidate (`+1` for each constraint that matches, eliminated on mismatch, `+0` on `nil`). The highest scorer wins; ties are flagged as `ambiguous_relation`. A link `[fig:diagram](#)` resolving against a FIGURE matches `XREF_FIGURE` (selector `#` + target_type_ref `FIGURE` = 2) over the generic `LABEL_REF` (selector `#` only = 1).

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
3. Write each type as one descriptor: pick the `kind`, fill `schema`, return `{ kind, schema, hooks }`.
4. Add a hook to `hooks` only if you need custom behaviour — pick the hook whose name matches the intent.
5. Set `template: <name>` in `project.yaml`.
6. Run `specc build` and inspect the output.
7. Add a verification descriptor if the domain has rules to enforce (see [Verification views](#verification-views)).

## Verification views

Verification views are SQL-based validation rules that run during the VERIFY phase. Each one is a descriptor with `kind = "verification"`: its `schema` holds the SQL that creates a database view, and its `message` hook turns each row the view returns into a diagnostic.

Place verification files under `models/<name>/verification_views/`. The loader scans that directory automatically — file names don't need a particular convention, but matching the `policy_key` helps (e.g. `vc_missing_hlr.lua`).

```src.lua:src-model-verification-view{caption="models/mymodel/verification_views/vc_missing_hlr.lua"}
return {
    kind = "verification",
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
        -- VERIFY: one call per row the SQL view returns. ctx.subject.row is the row.
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "Verification case '%s' has no traceability link to an HLR", label)
        end,
    },
}
```

`policy_key` is the handle authors use to tune severity. Repeating a `policy_key` in an overlay replaces the earlier descriptor in place; setting `disabled = true` in the `schema` removes it entirely (model layering). Suppress a verification view in `project.yaml` via its `policy_key`:

```src.yaml:src-model-suppress-verification-view{caption="Suppressing a verification view"}
validation:
  traceability_vc_to_hlr: ignore
```

## External renderers

Float and view types that need an external tool (PlantUML, ECharts, Graphviz, …) set `needs_external_render = true` and declare a pair of float data hooks: `prepare_task` builds the spawn task, and `handle_result` writes the resolved AST once the tool finishes. The pipeline collects every such item, spawns the processes in parallel, and dispatches each result back through `handle_result`.

These two hooks are the external counterpart to `transform`. A float declares **either** an internal `transform` **or** the external `prepare_task` + `handle_result` pair — never both. (Declaring `render` alongside the external pair is also rejected.)

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
        -- DATA: build the spawn task. dctx.subject carries { float, build_dir };
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
        -- { task, success, stdout, stderr }; dctx.data is the SpecIR database.
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
  - Process to spawn and its options. `opts.timeout` is in milliseconds; `opts.cwd` sets the working directory.
* - `output_path`
  - File-based cache key. If the file already exists, the process is not spawned — `handle_result` runs immediately with the cached path. Put the content hash in the filename so input changes trigger a fresh render.
* - `context`
  - Arbitrary table passed through to `handle_result` (read as `task.context`).
```

The same mechanism works for **views** — `math_inline` uses it to convert AsciiMath to OMML. The render handler queries the view rows (instead of float rows) for view-typed items.

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

**My type doesn't load.** Check that the file is under `types/<category>/<name>.lua`, that the category is one of `{objects, floats, views, relations, specifications}`, and that the module **returns its descriptor table**. The descriptor's `kind` must match the directory; a mismatch is a hard error. Non-view categories fail loudly; view load failures become warnings on stderr — watch the build output.

**The host rejected my hook.** Each hook name is valid only for certain kinds (see [list-table:tbl-model-hook-catalogue](#)). A name that isn't allowed for the kind, or a function hung off a top-level key other than `hooks`, is a loud register-time error — by design, so behaviour never silently fails to fire. Move behaviour into `hooks` and check the spelling.

**My override isn't taking effect.** Overrides replace by `schema.id`, not by filename. The custom type must declare the **same `id`** as the default (case-sensitive). The filename is irrelevant.

**My render hook produces nothing.** A view that `extends = "TABLE_VIEW"` but declares no `build_block` is a load error — add the `build_block` data hook. For an object, remember that returning `nil` leaves the original element untouched; return the blocks you built.

**My external renderer runs every build even without changes.** Your `output_path` isn't content-addressed. Include the content hash in the filename so unchanged input hits the file-based cache.

## Pointers

- [User manual](../manual.md) — day-to-day authoring syntax.
- Engineering docs — the [type system SDD](../../engineering_docs/architecture/type_system.md) is the authoritative contract; [type discovery](../../engineering_docs/architecture/type_discovery_design.md) and [model design](../../engineering_docs/architecture/model_design.md) cover internals.
- [Concepts dictionary](../../engineering_docs/dictionary/concepts.md) — vocabulary reference.
