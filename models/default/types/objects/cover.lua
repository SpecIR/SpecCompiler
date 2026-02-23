---Cover Page object type for the default model.
---Emits semantic Divs converted by the DOCX filter to styled OOXML paragraphs.
---
---Usage:
---  ## COVER: My Report Title
---  > subtitle: A Comprehensive Analysis
---  > author: Jane Smith
---  > date: 2026-02-21
---  > document_id: DOC-001
---  > version: 1.0

local render_utils = require("pipeline.shared.render_utils")

local M = {}

M.name = "cover"

M.object = {
    id = "COVER",
    long_name = "Cover Page",
    description = "Document cover page (title, author, date, version)",
    is_composite = false,
    numbered = false,
    implicit_aliases = { "cover", "cover page", "title page" },
    header_style_id = "",
    body_style_id = nil,
    attributes = {
        { name = "subtitle",    type = "STRING" },
        { name = "author",      type = "STRING" },
        { name = "date",        type = "STRING" },
        { name = "version",     type = "STRING" },
        { name = "document_id", type = "STRING" },
    },
}

-- Semantic helpers

local function semantic_div(text, class)
    local div = pandoc.Div({pandoc.Para({pandoc.Str(text)})})
    div.classes = {class}
    return div
end

local function vertical_space(twips)
    return pandoc.RawBlock("speccompiler", "vertical-space:" .. tostring(twips))
end

local function get_spec_attributes(db, spec_ref)
    if not db or not spec_ref then return {} end

    local results = db:query_all([[
        SELECT name, string_value, raw_value
        FROM spec_attribute_values
        WHERE specification_ref = :spec_ref
          AND owner_object_id IS NULL
          AND owner_float_id IS NULL
    ]], {spec_ref = spec_ref})

    local attrs = {}
    if results then
        for _, row in ipairs(results) do
            local name = row.name and row.name:lower() or ""
            attrs[name] = row.string_value or row.raw_value or ""
        end
    end
    return attrs
end

function M.on_render_SpecObject(obj, ctx)
    local blocks = {}

    local obj_attrs = ctx.attributes or {}
    local spec_attrs = get_spec_attributes(ctx.db, ctx.spec_id)

    local function get(name)
        local lower = name:lower()
        local val = obj_attrs[lower]
        if type(val) == "table" then val = val.value end
        if val and val ~= "" then return val end
        val = obj_attrs[name:upper()]
        if type(val) == "table" then val = val.value end
        if val and val ~= "" then return val end
        return spec_attrs[lower]
    end

    local title       = obj.title_text or get("title")
    local subtitle    = get("subtitle")
    local author      = get("author")
    local date        = get("date")
    local version     = get("version")
    local document_id = get("document_id")

    -- If no title, fall back to original blocks
    if not title or title == "" then
        return ctx.original_blocks
    end

    -- Cover layout:
    -- 1. Vertical space (~2 inches from top)
    -- 2. Title (large, centered)
    -- 3. Subtitle (if present)
    -- 4. Vertical space
    -- 5. Author
    -- 6. Date
    -- 7. Version / Document ID at bottom

    -- Mark cover section start so output filters can strip/keep as a unit
    table.insert(blocks, pandoc.RawBlock("speccompiler", "cover-section-start"))

    table.insert(blocks, vertical_space(2880))  -- ~2 inches

    table.insert(blocks, semantic_div(title, "cover-title"))

    if subtitle then
        table.insert(blocks, semantic_div(subtitle, "cover-subtitle"))
    end

    table.insert(blocks, vertical_space(2160))  -- ~1.5 inches

    if author then
        table.insert(blocks, semantic_div(author, "cover-author"))
    end

    if date then
        table.insert(blocks, semantic_div(date, "cover-date"))
    end

    table.insert(blocks, vertical_space(1440))  -- ~1 inch

    if document_id then
        table.insert(blocks, semantic_div(document_id, "cover-docid"))
    end

    if version then
        table.insert(blocks, semantic_div("v" .. version, "cover-version"))
    end

    -- Page break after cover
    render_utils.add_page_break(blocks, "next")

    -- Mark cover section end
    table.insert(blocks, pandoc.RawBlock("speccompiler", "cover-section-end"))

    return blocks
end

return M
