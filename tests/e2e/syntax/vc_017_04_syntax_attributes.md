# Attribute Test @SPEC-ATTR-001

> string_attr: Simple string value

> integer_attr: 42

> boolean_attr: true

> date_attr: 2025-01-05

## Multi-line Attributes @SEC-MULTI

Section with multi-line attribute.

> description:
> This is a multi-line attribute value
> that spans several lines and should be
> captured as a single rich text block.

> list_attr:
> - Item one
> - Item two
> - Item three

## Type Casting (WRONG) @SEC-CAST-WRONG

Testing different attribute types.

> count: 100

> enabled: false

> ratio: 0.75

> created: 2024-12-01

Actually this is just one type....

## Type Casting (FIX) @SEC-CAST

Testing different attribute types.

> count: 100

> enabled: false

> ratio: 0.75

> created: 2024-12-01

## Multi-line with Inline Content @SEC-INLINE-MULTI

Testing multi-line attribute that has content on first line AND continuation blocks.
This reproduces the bug from docs/core/pipeline/design.md.

> description: The Pipeline module (`core/pipeline.lua`) provides:
>
> **Constructor**: `Pipeline.new(opts)` creates instance with:
> - `log`: Logger adapter for debug/info/warn messages
> - `diagnostics`: Diagnostics collector for errors/warnings
> - `data`: DataManager instance for database operations
> - `config`: Preset configuration (styles, captions, validation)
> - `project_info`: Full project metadata (template, files, output_dir)
>
> **Handler Registry**: Internal `handlers` table maps handler names to handler objects. Registration validates name uniqueness and required fields.
>
> **Phase Constants**: `M.PHASES` enumeration defines canonical phase names:
> ```lua
> M.PHASES = {
>     INITIALIZE = "initialize",
>     ANALYZE    = "analyze",
>     VERIFY     = "verify",
>     TRANSFORM  = "transform",
>     EMIT       = "emit"
> }
> ```
>
> **Execution**: `execute(docs)` builds contexts from input documents and runs phases sequentially, aborting after VERIFY if errors exist.

