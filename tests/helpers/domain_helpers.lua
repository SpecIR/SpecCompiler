-- Domain helpers for SpecCompiler test oracles
-- Provides constructors for common SpecCompiler AST structures
-- Uses raw Pandoc API internally

local M = {}

-- ============================================================================
-- Specification Structures
-- ============================================================================

---Create a specification title Div.
---Renders as a styled Div (not Header) to avoid affecting section numbering.
---@param id string Specification identifier (e.g., "SRS-001")
---@param title string Title text
---@param opts table|nil Optional {style = "Title", show_pid = false}
---@return Pandoc.Div
function M.SpecTitle(id, title, opts)
    opts = opts or {}
    local style = opts.style or "Title"

    local title_inlines = {}
    if opts.show_pid and id ~= "" then
        table.insert(title_inlines, pandoc.Str(id))
        table.insert(title_inlines, pandoc.Str(": "))
    end
    table.insert(title_inlines, pandoc.Str(title))

    return pandoc.Div(
        {pandoc.Para(title_inlines)},
        pandoc.Attr(id, {"spec-title"}, {["custom-style"] = style})
    )
end

---Create a spec object header (HLR, LLR, etc.).
---@param level number Header level (1-6)
---@param id string Object identifier/anchor
---@param title string|table Title as string or array of Pandoc inlines
---@param opts table|nil Optional {data_pos, classes, append_id = true}
---@return Pandoc.Header
function M.SpecHeader(level, id, title, opts)
    opts = opts or {}
    local attrs = {}

    if opts.data_pos then
        attrs["data-pos"] = opts.data_pos
    end

    -- Build title inlines
    local title_inlines
    if type(title) == "string" then
        title_inlines = {pandoc.Str(title)}
        -- Optionally append " @ID" suffix
        if opts.append_id ~= false and id ~= "" then
            table.insert(title_inlines, pandoc.Space())
            table.insert(title_inlines, pandoc.Str("@" .. id))
        end
    else
        title_inlines = title
    end

    return pandoc.Header(
        level,
        title_inlines,
        pandoc.Attr(id, opts.classes or {}, attrs)
    )
end

-- ============================================================================
-- Attribute Structures
-- ============================================================================

---Create an attribute blockquote (key: value pairs).
---@param attrs table Key-value pairs of attributes
---@param opts table|nil Optional {data_pos}
---@return Pandoc.Div Div containing BlockQuote with attributes
function M.AttributeBlock(attrs, opts)
    opts = opts or {}

    -- Build inline content for attributes
    local inlines = {}
    local first = true
    for k, v in pairs(attrs) do
        if not first then
            table.insert(inlines, pandoc.SoftBreak())
        end
        first = false
        table.insert(inlines, pandoc.Str(k .. ": " .. tostring(v)))
    end

    local inner_attrs = {}
    if opts.data_pos then
        inner_attrs["data-pos"] = opts.data_pos
    end

    local blockquote = pandoc.BlockQuote({
        pandoc.Div(
            {pandoc.Para(inlines)},
            pandoc.Attr("", {}, inner_attrs)
        )
    })

    local outer_attrs = {}
    if opts.outer_data_pos then
        outer_attrs["data-pos"] = opts.outer_data_pos
    end

    return pandoc.Div({blockquote}, pandoc.Attr("", {}, outer_attrs))
end

---Create a simple body paragraph wrapped in Div.
---@param text string|table Text as string or array of Pandoc inlines
---@param opts table|nil Optional {data_pos}
---@return Pandoc.Div
function M.BodyPara(text, opts)
    opts = opts or {}
    local attrs = {}

    if opts.data_pos then
        attrs["data-pos"] = opts.data_pos
    end

    local inlines
    if type(text) == "string" then
        inlines = {pandoc.Str(text)}
    else
        inlines = text
    end

    return pandoc.Div(
        {pandoc.Para(inlines)},
        pandoc.Attr("", {}, attrs)
    )
end

-- ============================================================================
-- Complete Requirement Structure
-- ============================================================================

---Create a complete requirement structure (header + body + attributes).
---Returns an array of blocks that can be concatenated into the document.
---@param opts table {id, level, title, body, attributes, data_pos, body_pos, attr_pos}
---@return table Array of Pandoc blocks
function M.Requirement(opts)
    local blocks = {}

    -- Header
    table.insert(blocks, M.SpecHeader(
        opts.level or 2,
        opts.id,
        opts.title,
        {data_pos = opts.data_pos, append_id = opts.append_id}
    ))

    -- Body paragraph
    if opts.body then
        table.insert(blocks, M.BodyPara(opts.body, {data_pos = opts.body_pos}))
    end

    -- Attribute block
    if opts.attributes then
        table.insert(blocks, M.AttributeBlock(opts.attributes, {
            data_pos = opts.attr_inner_pos,
            outer_data_pos = opts.attr_pos
        }))
    end

    return blocks
end

-- ============================================================================
-- Relation Structures
-- ============================================================================

---Create a relation link element.
---@param target_id string Target object identifier
---@param opts table|nil Optional {relation_type, text}
---@return Pandoc.Link
function M.Relation(target_id, opts)
    opts = opts or {}
    local text = opts.text or target_id

    local link_attrs = {}
    if opts.relation_type then
        link_attrs["data-relation"] = opts.relation_type
    end

    return pandoc.Link(
        {pandoc.Str(text)},
        "#" .. target_id,
        "",
        pandoc.Attr("", {}, link_attrs)
    )
end

-- ============================================================================
-- Float Structures
-- ============================================================================

---Create a bookmark start RawBlock.
---@param bookmark_id string Bookmark identifier
---@param anchor_id string Anchor identifier
---@return Pandoc.RawBlock
function M.BookmarkStart(bookmark_id, anchor_id)
    return pandoc.RawBlock("speccompiler", "bookmark-start:" .. bookmark_id .. ":" .. anchor_id)
end

---Create a bookmark end RawBlock.
---@param bookmark_id string Bookmark identifier
---@return Pandoc.RawBlock
function M.BookmarkEnd(bookmark_id)
    return pandoc.RawBlock("speccompiler", "bookmark-end:" .. bookmark_id)
end

---Create a float caption Div.
---@param caption_text string Caption text
---@param opts table {float_id, float_type, prefix, seq_name, separator, style}
---@return Pandoc.Div
function M.FloatCaption(caption_text, opts)
    opts = opts or {}

    local attrs = {
        ["separator"] = opts.separator or " ",
        ["float-type"] = opts.float_type or "TABLE",
        ["prefix"] = opts.prefix or "Table",
        ["seq-name"] = opts.seq_name or "TABLE",
        ["float-id"] = opts.float_id or "",
        ["style"] = opts.style or "Caption"
    }

    return pandoc.Div(
        {pandoc.Para({pandoc.Str(caption_text)})},
        pandoc.Attr("", {"speccompiler-caption"}, attrs)
    )
end

---Create a table float structure (bookmark + caption + table + bookmark-end).
---@param opts table {id, bookmark_id, caption, table_content, float_type, prefix}
---@return table Array of Pandoc blocks
function M.TableFloat(opts)
    local blocks = {}
    local bookmark_id = opts.bookmark_id or ("bm_" .. opts.id)

    -- Bookmark start
    table.insert(blocks, M.BookmarkStart(bookmark_id, opts.id))

    -- Caption
    table.insert(blocks, M.FloatCaption(opts.caption or "", {
        float_id = opts.id,
        float_type = opts.float_type or "TABLE",
        prefix = opts.prefix or "Table",
        seq_name = opts.seq_name or "TABLE",
        separator = opts.separator,
        style = opts.style
    }))

    -- Table content (caller provides Pandoc.Table)
    if opts.table_content then
        table.insert(blocks, opts.table_content)
    end

    -- Bookmark end
    table.insert(blocks, M.BookmarkEnd(bookmark_id))

    return blocks
end

---Create a figure float structure.
---@param opts table {id, bookmark_id, caption, image_src, alt_text, float_type, prefix}
---@return table Array of Pandoc blocks
function M.FigureFloat(opts)
    local blocks = {}
    local bookmark_id = opts.bookmark_id or ("bm_" .. opts.id)

    -- Bookmark start
    table.insert(blocks, M.BookmarkStart(bookmark_id, opts.id))

    -- Caption
    table.insert(blocks, M.FloatCaption(opts.caption or "", {
        float_id = opts.id,
        float_type = opts.float_type or "FIGURE",
        prefix = opts.prefix or "Figure",
        seq_name = opts.seq_name or "FIGURE",
        separator = opts.separator,
        style = opts.style
    }))

    -- Image content
    if opts.image_src then
        local img = pandoc.Image(
            {pandoc.Str(opts.alt_text or "")},
            opts.image_src,
            opts.title or ""
        )
        table.insert(blocks, pandoc.Para({img}))
    end

    -- Bookmark end
    table.insert(blocks, M.BookmarkEnd(bookmark_id))

    return blocks
end

---Create a listing/code float structure.
---@param opts table {id, bookmark_id, caption, code, language, float_type, prefix}
---@return table Array of Pandoc blocks
function M.ListingFloat(opts)
    local blocks = {}
    local bookmark_id = opts.bookmark_id or ("bm_" .. opts.id)

    -- Bookmark start
    table.insert(blocks, M.BookmarkStart(bookmark_id, opts.id))

    -- Caption
    table.insert(blocks, M.FloatCaption(opts.caption or "", {
        float_id = opts.id,
        float_type = opts.float_type or "LISTING",
        prefix = opts.prefix or "Listing",
        seq_name = opts.seq_name or "LISTING",
        separator = opts.separator,
        style = opts.style
    }))

    -- Code block
    if opts.code then
        local code_attrs = pandoc.Attr("", {opts.language or ""}, {})
        table.insert(blocks, pandoc.CodeBlock(opts.code, code_attrs))
    end

    -- Bookmark end
    table.insert(blocks, M.BookmarkEnd(bookmark_id))

    return blocks
end

-- ============================================================================
-- Utility Functions
-- ============================================================================

---Flatten an array of block arrays into a single array.
---Useful when combining multiple Requirement() or Float() results.
---@param block_arrays table Array of block arrays
---@return table Flattened array of blocks
function M.flatten(block_arrays)
    local result = {}
    for _, arr in ipairs(block_arrays) do
        if type(arr) == "table" and arr.t then
            -- Single block element
            table.insert(result, arr)
        else
            -- Array of blocks
            for _, block in ipairs(arr) do
                table.insert(result, block)
            end
        end
    end
    return result
end

---Create inline text with spans (for position tracking).
---@param parts table Array of {text, data_pos} pairs
---@return table Array of Pandoc inlines
function M.SpannedText(parts)
    local inlines = {}
    for _, part in ipairs(parts) do
        local text, pos = part[1], part[2]
        if pos then
            table.insert(inlines, pandoc.Span(
                {pandoc.Str(text)},
                pandoc.Attr("", {}, {["data-pos"] = pos})
            ))
        else
            table.insert(inlines, pandoc.Str(text))
        end
    end
    return inlines
end

return M
