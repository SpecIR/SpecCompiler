---Cover Page object type for the default model.
---Emits semantic Divs converted by the DOCX filter to styled OOXML paragraphs.
---
---Usage:
---  # SPEC: My Report Title @DOC-001
---  > subtitle: A Comprehensive Analysis
---  > author: Jane Smith
---  > date: 2026-02-21
---  > version: 1.0
---
---  ## COVER: Cover @COVER

local render_utils = require("pipeline.shared.render_utils")

-- Semantic helpers

local function semantic_div(text, class)
    local div = pandoc.Div({pandoc.Para({pandoc.Str(text)})})
    div.classes = {class}
    return div
end

local function vertical_space(twips)
    return pandoc.RawBlock("speccompiler", "vertical-space:" .. tostring(twips))
end

local function value_from(attrs, name)
    if not attrs then return nil end
    local lower = name:lower()
    local val = attrs[lower] or attrs[name] or attrs[name:upper()]
    if type(val) == "table" then val = val.value or val.raw_value end
    if val and val ~= "" then return tostring(val) end
    return nil
end

local function compact_meta(parts)
    local out = {}
    for _, part in ipairs(parts) do
        if part and part ~= "" then table.insert(out, part) end
    end
    if #out == 0 then return nil end
    return table.concat(out, " | ")
end

return {
    kind = "object",
    schema = {
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
    },
    hooks = {
        render = function(ctx)
            local blocks = {}

            local obj = ctx.subject.object or {}
            local obj_attrs = ctx.subject.attributes or {}
            local spec_attrs = ctx.subject.spec_attributes or {}
            local spec = ctx.subject.specification or {}

            local function get_spec(name)
                return value_from(spec_attrs, name)
            end

            local function get_override(name)
                return value_from(obj_attrs, name)
            end

            local title = get_override("title")
                or spec.long_name
                or get_spec("title")
                or obj.title_text
            local subtitle = get_override("subtitle")
                or get_spec("subtitle")
                or spec.type_ref
            local author = get_override("author") or get_spec("author")
            local date = get_override("date") or get_spec("date") or get_spec("release_date")
            local version = get_override("version") or get_spec("version") or get_spec("revision")
            local status = get_override("status") or get_spec("status") or get_spec("stage")
            local document_id = get_override("document_id")
                or get_spec("document_id")
                or spec.pid
                or spec.identifier

            -- If no title, fall back to original blocks
            if not title or title == "" then
                return ctx.subject.element
            end

            local date_status = compact_meta({ date, status })

            -- Cover layout:
            -- 1. Vertical space
            -- 2. Title (large, centered)
            -- 3. Subtitle (if present)
            -- 4. Document metadata
            -- 5. Author
            -- 6. Version / date / status

            -- Mark cover section start so output filters can strip/keep as a unit
            table.insert(blocks, pandoc.RawBlock("speccompiler", "cover-section-start"))

            table.insert(blocks, vertical_space(2520))  -- ~1.75 inches

            table.insert(blocks, semantic_div(title, "cover-title"))

            if subtitle then
                table.insert(blocks, semantic_div(subtitle, "cover-subtitle"))
            end

            table.insert(blocks, vertical_space(1080))  -- ~0.75 inch

            if document_id then
                table.insert(blocks, semantic_div(document_id, "cover-docid"))
            end

            if author then
                table.insert(blocks, semantic_div(author, "cover-author"))
            end

            if date_status then
                table.insert(blocks, semantic_div(date_status, "cover-date"))
            end

            table.insert(blocks, vertical_space(720))  -- ~0.5 inch

            if version then
                table.insert(blocks, semantic_div("Version " .. version, "cover-version"))
            end

            -- Page break after cover
            render_utils.add_page_break(blocks, "next")

            -- Mark cover section end
            table.insert(blocks, pandoc.RawBlock("speccompiler", "cover-section-end"))

            return blocks
        end,
    },
}
