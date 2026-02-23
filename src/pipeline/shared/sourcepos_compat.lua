---Pandoc sourcepos compatibility layer.
---
---Normalizes inline `data-pos` tracking spans across Pandoc versions.
---
---Background:
---  - Pandoc < 3.1.10 (commonmark-pandoc < 0.2.2): wraps every inline in
---    Span("", [], [("data-pos", "...")]).
---  - Pandoc >= 3.1.10 (commonmark-pandoc >= 0.2.2): same wrapping but also
---    adds wrapper="1" attribute on auto-generated Spans/Divs.
---
---The pipeline only uses block-level data-pos for diagnostics (line numbers).
---Inline tracking spans are noise that differs across Pandoc versions.
---This module strips them early so the AST is version-independent.
---
---Exception: Link elements receive the data-pos from their wrapping tracking
---Span before it is discarded, enabling precise line:col error reporting.

local M = {}

---Check if a Span is a sourcepos tracking span (not user-authored).
---Matches both pre-3.1.10 (data-pos only) and post-3.1.10 (data-pos + wrapper).
---@param elem table Pandoc inline element
---@return boolean
local function is_tracking_span(elem)
    if not elem or elem.t ~= "Span" then return false end

    local id = elem.identifier or ""
    local classes = elem.classes or {}

    if id ~= "" or #classes > 0 then return false end

    local attrs = elem.attributes or {}
    local has_data_pos = false
    local attr_count = 0

    for k, _ in pairs(attrs) do
        attr_count = attr_count + 1
        if k == "data-pos" then
            has_data_pos = true
        elseif k ~= "wrapper" then
            -- Has an attribute that is neither data-pos nor wrapper
            return false
        end
    end

    return has_data_pos and attr_count <= 2
end

---Remove the `wrapper` attribute from an element's Attr.
---Pandoc >= 3.1.10 adds wrapper="1" to auto-generated Divs/Spans;
---the pipeline never uses it.
---@param attr pandoc.Attr
---@return pandoc.Attr
local function strip_wrapper_attr(attr)
    if not attr or not attr.attributes or not attr.attributes.wrapper then
        return attr
    end
    local new_attrs = {}
    for k, v in pairs(attr.attributes) do
        if k ~= "wrapper" then
            new_attrs[k] = v
        end
    end
    return pandoc.Attr(attr.identifier, attr.classes, new_attrs)
end

---Merge adjacent Str tokens into single Str.
---@param inlines table Array of inline elements
---@return table
local function merge_adjacent_strs(inlines)
    if not inlines or #inlines == 0 then return inlines end

    local result = {}
    local pending = nil

    for _, inline in ipairs(inlines) do
        if inline.t == "Str" then
            if pending then
                pending = pending .. inline.text
            else
                pending = inline.text
            end
        else
            if pending then
                table.insert(result, pandoc.Str(pending))
                pending = nil
            end
            table.insert(result, inline)
        end
    end

    if pending then
        table.insert(result, pandoc.Str(pending))
    end

    return result
end

---Transfer data-pos from a tracking Span to a Link element by reconstructing it.
---@param link table Pandoc Link element
---@param pos string data-pos value (e.g., "24:5-24:20")
---@return table link New Link with data-pos in its attributes
local function transfer_pos_to_link(link, pos)
    local new_attrs = {}
    if link.attr and link.attr.attributes then
        for k, v in pairs(link.attr.attributes) do
            new_attrs[k] = v
        end
    end
    new_attrs["data-pos"] = pos
    local new_attr = pandoc.Attr(
        link.attr and link.attr.identifier or "",
        link.attr and link.attr.classes or {},
        new_attrs
    )
    return pandoc.Link(link.content, link.target, link.title, new_attr)
end

---Strip tracking spans from an inline list, unwrapping their content.
---When a tracking Span wraps a Link, the Span's data-pos is transferred
---to the Link's own attributes for precise diagnostic reporting.
---@param inlines pandoc.Inlines
---@return pandoc.Inlines
local function strip_inlines(inlines)
    if not inlines then return inlines end

    local result = {}
    for _, inline in ipairs(inlines) do
        if is_tracking_span(inline) then
            local span_pos = inline.attributes and inline.attributes["data-pos"]
            -- Recursively strip nested tracking spans from inner content
            local stripped_inner = strip_inlines(inline.content or {})
            for _, inner in ipairs(stripped_inner) do
                if span_pos and inner.t == "Link"
                   and not (inner.attr and inner.attr.attributes and inner.attr.attributes["data-pos"]) then
                    -- Transfer tracking Span's data-pos to Link for precise diagnostics
                    table.insert(result, transfer_pos_to_link(inner, span_pos))
                else
                    table.insert(result, inner)
                end
            end
        elseif inline.t == "Span" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Span(stripped, inline.attr))
        elseif inline.t == "Link" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Link(stripped, inline.target, inline.title, inline.attr))
        elseif inline.t == "Image" then
            local stripped = strip_inlines(inline.caption or {})
            table.insert(result, pandoc.Image(stripped, inline.src, inline.title, inline.attr))
        elseif inline.t == "Emph" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Emph(stripped))
        elseif inline.t == "Strong" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Strong(stripped))
        elseif inline.t == "Strikeout" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Strikeout(stripped))
        elseif inline.t == "Superscript" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Superscript(stripped))
        elseif inline.t == "Subscript" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Subscript(stripped))
        elseif inline.t == "Quoted" then
            local stripped = strip_inlines(inline.content or {})
            table.insert(result, pandoc.Quoted(inline.quotetype, stripped))
        elseif inline.t == "Note" then
            local stripped_blocks = M.strip_tracking_spans_blocks(inline.content or {})
            table.insert(result, pandoc.Note(stripped_blocks))
        else
            table.insert(result, inline)
        end
    end

    return merge_adjacent_strs(result)
end

---Strip tracking spans from a list of blocks.
---@param blocks table Array of Pandoc blocks
---@return table
function M.strip_tracking_spans_blocks(blocks)
    if not blocks then return blocks end

    local result = {}
    for _, block in ipairs(blocks) do
        if block.t == "Para" then
            table.insert(result, pandoc.Para(strip_inlines(block.content)))
        elseif block.t == "Plain" then
            table.insert(result, pandoc.Plain(strip_inlines(block.content)))
        elseif block.t == "Header" then
            table.insert(result, pandoc.Header(block.level, strip_inlines(block.content), strip_wrapper_attr(block.attr)))
        elseif block.t == "Div" then
            table.insert(result, pandoc.Div(M.strip_tracking_spans_blocks(block.content), strip_wrapper_attr(block.attr)))
        elseif block.t == "BlockQuote" then
            table.insert(result, pandoc.BlockQuote(M.strip_tracking_spans_blocks(block.content)))
        elseif block.t == "BulletList" then
            local items = {}
            for _, item in ipairs(block.content) do
                table.insert(items, M.strip_tracking_spans_blocks(item))
            end
            table.insert(result, pandoc.BulletList(items))
        elseif block.t == "OrderedList" then
            local items = {}
            for _, item in ipairs(block.content) do
                table.insert(items, M.strip_tracking_spans_blocks(item))
            end
            table.insert(result, pandoc.OrderedList(items, block.listAttributes))
        elseif block.t == "DefinitionList" then
            local items = {}
            for _, item in ipairs(block.content) do
                local term = strip_inlines(item[1])
                local defs = {}
                for _, def in ipairs(item[2]) do
                    table.insert(defs, M.strip_tracking_spans_blocks(def))
                end
                table.insert(items, { term, defs })
            end
            table.insert(result, pandoc.DefinitionList(items))
        elseif block.t == "Table" then
            -- Tables have inline content in cells; use Pandoc walk for efficiency
            local walked = pandoc.walk_block(block, {
                Span = function(span)
                    if is_tracking_span(span) then
                        return span.content
                    end
                end
            })
            table.insert(result, walked)
        else
            table.insert(result, block)
        end
    end

    return result
end

---Strip inline tracking spans from a Pandoc document.
---Preserves block-level data-pos attributes for diagnostics.
---@param doc pandoc.Pandoc
---@return pandoc.Pandoc
function M.normalize(doc)
    if not doc then return doc end
    doc.blocks = M.strip_tracking_spans_blocks(doc.blocks)
    return doc
end

return M
