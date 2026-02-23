# Guide: DOCX Customization

## Introduction

SpecCompiler generates DOCX output through a multi-stage pipeline:

1. **SpecIR** -- Structured data in SQLite (objects, relations, floats, attributes).
2. **Pandoc AST** -- The emitter assembles a Pandoc document from the SpecIR.
3. **Pandoc DOCX Writer** -- Pandoc converts the AST to DOCX using a `reference.docx` for styles.
4. **Lua Filter** -- A format-specific filter converts SpecCompiler markers to OOXML (captions, bookmarks, math).
5. **Postprocessor** -- Manipulates the generated DOCX ZIP archive (positioned floats, caption orphan prevention, template-specific OOXML).

Customization is available at three levels: **style presets** (fonts, spacing, page layout), **filters** (AST-to-OOXML conversion), and **postprocessors** (raw OOXML manipulation).

## How Pandoc reference.docx Works

Pandoc uses a reference document as a style template for DOCX output. The reference document defines paragraph styles (Normal, Heading 1, Caption, etc.), page dimensions, margins, and default formatting. Pandoc does **not** copy content from the reference document -- only styles and settings.

SpecCompiler manages the reference document in two ways:

1. **Auto-generated from presets** (default): SpecCompiler builds a `reference.docx` from Lua style presets, storing it at `{output_dir}/reference.docx`.
2. **User-provided**: Set `docx.reference_doc` in `project.yaml` to use your own Word template.

## Style Presets

Style presets are Lua files that declaratively define DOCX styles. They are located at:

```
models/{template}/styles/{preset}/preset.lua
```

### Preset Table Structure

A preset file returns a Lua table with the following top-level keys:

```src.lua:src-docx-preset-structure{caption="Preset table structure"}
return {
    name = "My Preset",
    description = "Custom document styles",

    -- Page configuration
    page = {
        size = "A4",              -- "Letter" or "A4"
        orientation = "portrait", -- "portrait" or "landscape"
        margins = {
            top = "2.5cm",
            bottom = "2.5cm",
            left = "3cm",
            right = "2cm",
        },
    },

    -- Paragraph styles (array of style definitions)
    paragraph_styles = { ... },

    -- Table styles (array of table style definitions)
    table_styles = { ... },

    -- Caption formats per float type
    captions = { ... },

    -- Document settings
    settings = {
        default_tab_stop = 720,   -- In twips (720 = 0.5 inch)
        language = "en-US",
    },

    -- Optional: inherit from another preset
    extends = {
        template = "default",     -- Base template
        preset = "base",          -- Base preset name
    },
}
```

### Paragraph Style Fields

```list-table:tbl-docx-paragraph-style{caption="Paragraph style fields"}
> header-rows: 1
> aligns: l,l,l,l

* - Field
  - Type
  - Default
  - Description
* - `id`
  - string
  - required
  - Internal style ID (e.g., "Heading1")
* - `name`
  - string
  - required
  - Display name in Word (e.g., "Heading 1")
* - `based_on`
  - string
  - nil
  - Parent style ID for inheritance
* - `next`
  - string
  - nil
  - Style to apply to the next paragraph
* - `font.name`
  - string
  - nil
  - Font family name
* - `font.size`
  - number
  - nil
  - Font size in points
* - `font.color`
  - string
  - nil
  - Hex color without `#` (e.g., "2F5496")
* - `font.bold`
  - boolean
  - nil
  - Bold text
* - `font.italic`
  - boolean
  - nil
  - Italic text
* - `spacing.line`
  - number
  - nil
  - Line spacing multiplier (1.0 = single, 1.15, 2.0, etc.)
* - `spacing.before`
  - number
  - nil
  - Space before paragraph in points
* - `spacing.after`
  - number
  - nil
  - Space after paragraph in points
* - `alignment`
  - string
  - nil
  - Text alignment: "left", "center", "right", "both" (justified)
* - `indent.left`
  - string
  - nil
  - Left indent (e.g., "0.5in", "1cm")
* - `indent.right`
  - string
  - nil
  - Right indent
* - `keep_next`
  - boolean
  - nil
  - Keep with next paragraph (prevent orphaning)
* - `outline_level`
  - integer
  - nil
  - Outline level for TOC (0 = Heading 1, 1 = Heading 2, etc.)
```

### Paragraph Style Example

```src.lua:src-docx-paragraph-styles{caption="Paragraph style definitions"}
paragraph_styles = {
    {
        id = "Normal",
        name = "Normal",
        font = { name = "Calibri", size = 11 },
        spacing = { line = 1.15, after = 8 },
        alignment = "left",
    },
    {
        id = "Heading1",
        name = "Heading 1",
        based_on = "Normal",
        next = "Normal",
        font = { name = "Calibri Light", size = 16, color = "2F5496" },
        spacing = { before = 12, after = 0, line = 1.15 },
        keep_next = true,
        outline_level = 0,
    },
    {
        id = "Caption",
        name = "Caption",
        based_on = "Normal",
        font = { name = "Calibri", size = 9, italic = true },
        spacing = { before = 0, after = 10, line = 1.15 },
    },
}
```

### Table Styles

```src.lua:src-docx-table-styles{caption="Table style definition"}
table_styles = {
    {
        id = "TableGrid",
        name = "Table Grid",
        borders = {
            top    = { style = "single", width = 0.5, color = "000000" },
            bottom = { style = "single", width = 0.5, color = "000000" },
            left   = { style = "single", width = 0.5, color = "000000" },
            right  = { style = "single", width = 0.5, color = "000000" },
            inside_h = { style = "single", width = 0.5, color = "000000" },
            inside_v = { style = "single", width = 0.5, color = "000000" },
        },
        cell_margins = {
            top = "0.05in",
            bottom = "0.05in",
            left = "0.08in",
            right = "0.08in",
        },
        autofit = true,
    },
}
```

### Caption Configuration

```src.lua:src-docx-captions{caption="Caption configuration per float type"}
captions = {
    figure = {
        template = "{prefix} {number}: {title}",
        prefix = "Figure",
        separator = ": ",
        style = "Caption",
    },
    table = {
        template = "{prefix} {number}: {title}",
        prefix = "Table",
        separator = ": ",
        style = "Caption",
    },
    listing = {
        template = "{prefix} {number}: {title}",
        prefix = "Listing",
        separator = ": ",
        style = "Caption",
    },
}
```

### Preset Inheritance

Presets can extend other presets using the `extends` field. The child preset deeply merges with the base, with child values taking precedence:

```src.lua:src-docx-preset-extends{caption="Preset inheritance"}
-- models/mymodel/styles/academic/preset.lua
return {
    name = "Academic",
    description = "Academic paper styles",

    extends = {
        template = "default",    -- Base template
        preset = "default",      -- Base preset name
    },

    -- Override only what changes
    page = {
        size = "A4",
        margins = { top = "2.5cm", bottom = "2.5cm", left = "3cm", right = "2cm" },
    },

    paragraph_styles = {
        {
            id = "Normal",
            name = "Normal",
            font = { name = "Times New Roman", size = 12 },
            spacing = { line = 1.5, after = 0 },
            alignment = "both",   -- Justified
        },
    },
}
```

The loader detects circular dependencies and reports them as errors.

### Format-Specific Style Overrides

Beyond the main `preset.lua`, you can provide format-specific style files:

- `models/{template}/styles/{preset}/docx.lua` -- DOCX-specific overrides
- `models/{template}/styles/{preset}/html.lua` -- HTML-specific overrides

These files return tables with keys like `float_styles` and `object_styles` that are merged with the base preset at emit time.

## Postprocessors

Postprocessors manipulate the generated DOCX file after Pandoc produces it. They operate on raw OOXML inside the ZIP archive.

### Loading

The base postprocessor (`models/default/postprocessors/docx.lua`) is always loaded. It handles:

- **Positioned floats** -- Converts inline images to anchored format with margin-relative positioning.
- **Caption orphan prevention** -- Adds `keepNext` to Caption-styled paragraphs.

Template-specific postprocessors are loaded from `models/{template}/postprocessors/docx.lua`.

### Hook Interface

A template postprocessor exports functions that are called in sequence:

```list-table:tbl-docx-postprocessor-hooks{caption="Postprocessor hook functions"}
> header-rows: 1
> aligns: l,l,l

* - Hook
  - Input
  - Purpose
* - `process_document(content, config, log)`
  - `document.xml` content
  - Modify main document body
* - `process_styles(content, log, config)`
  - `styles.xml` content
  - Modify or inject style definitions
* - `process_numbering(content, log)`
  - `numbering.xml` content
  - Modify list numbering definitions
* - `process_content_types(content, log)`
  - `[Content_Types].xml` content
  - Add content type declarations
* - `process_settings(content, log)`
  - `settings.xml` content
  - Modify document settings
* - `process_rels(content, log)`
  - `document.xml.rels` content
  - Add/modify relationship entries
* - `create_additional_parts(temp_dir, log, config)`
  - Temp directory path
  - Create new parts (headers, footers)
```

All hooks are optional. Each receives the current XML content as a string and returns the modified content.

### Writing a Custom Postprocessor

Create `models/mymodel/postprocessors/docx.lua`:

```src.lua:src-docx-custom-postprocessor{caption="Custom DOCX postprocessor"}
local M = {}

function M.process_document(content, config, log)
    local modified = content

    -- Example: Add custom watermark text to every paragraph
    -- (Real implementations would use proper OOXML patterns)

    log.debug("[MYMODEL-POST] Processing document.xml")
    return modified
end

function M.process_styles(content, log, config)
    local modified = content

    -- Example: Inject a custom paragraph style
    log.debug("[MYMODEL-POST] Processing styles.xml")
    return modified
end

return M
```

### The `config` Parameter

The `config` table passed to hooks contains:

- `template` -- The template name
- `docx` -- DOCX configuration from `project.yaml`
- `spec_metadata` -- Specification-level attributes (in `create_additional_parts`)

## Filters

Pandoc Lua filters run during the DOCX write phase and convert SpecCompiler format markers to OOXML. The default filter (`models/default/filters/docx.lua`) handles:

```list-table:tbl-docx-filter-features{caption="Default DOCX filter conversions"}
> header-rows: 1
> aligns: l,l

* - Input Marker
  - Output
* - `RawBlock("speccompiler", "page-break")`
  - OOXML page break
* - `RawBlock("speccompiler", "vertical-space:NNNN")`
  - OOXML spacing (in twips)
* - `RawBlock("speccompiler", "bookmark-start:ID:NAME")`
  - OOXML bookmark start
* - `RawBlock("speccompiler", "math-omml:OMML")`
  - OOXML math element
* - `Div.speccompiler-caption`
  - OOXML caption with SEQ field
* - `Div.speccompiler-numbered-equation`
  - OOXML numbered equation with tab layout
* - `Div.speccompiler-positioned-float`
  - Position markers for postprocessor
* - `Link` with `.ext` target
  - Rewritten to `.docx` target
```

### When to Use Filters vs Postprocessors

- **Filters** operate on the Pandoc AST before DOCX generation. Use them when you need to convert SpecCompiler markers to OOXML elements that Pandoc will then place in the document.
- **Postprocessors** operate on the raw OOXML after DOCX generation. Use them when you need to manipulate the final XML directly (style injection, image positioning, headers/footers).

## project.yaml Configuration

### DOCX-Specific Settings

```src.yaml:src-docx-project-config{caption="DOCX configuration in project.yaml"}
# Output format entry
outputs:
  - format: docx
    path: build/docx/{spec_id}.docx

# DOCX-specific configuration
docx:
  preset: default              # Style preset name
  # reference_doc: assets/reference.docx  # Custom reference (overrides preset)
```

### Configuration Precedence

1. If `docx.reference_doc` is set, that file is used directly as the Pandoc reference document.
2. If `docx.preset` is set (or defaults to the model's styles), SpecCompiler generates `{output_dir}/reference.docx` from the preset.
3. If neither is set, Pandoc uses its built-in default styles.

## Reference Document Cache

When using presets, SpecCompiler caches the generated `reference.docx` to avoid regenerating it on every build.

The cache works as follows:

1. Compute SHA-1 hash of the preset file content.
2. Compare against the stored hash in the `build_meta` table (key-value store in `specir.db`).
3. If the hashes match and `reference.docx` exists on disk, skip generation.
4. If the preset changed or `reference.docx` is missing, regenerate and update the cache.

To force regeneration of the reference document, delete it:

```src.bash:src-docx-force-reference{caption="Force reference document regeneration"}
rm -f build/reference.docx
./bin/speccompiler-core
```
