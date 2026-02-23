---Table of Contents view type module.
---Handles `toc:` inline code syntax for generating table of contents.
---
---Syntax:
---  `toc:`           - Full TOC with default settings
---  `toc: depth=2`   - TOC limited to depth 2
---
---Generates a speccompiler-toc Div wrapping a BulletList.
---Format-specific filters handle the Div:
---  - DOCX filter: Converts to native Word TOC field, marks preceding heading unnumbered
---  - HTML filter: Strips entirely (not needed in HTML output)
---
---Uses the unified INITIALIZE -> TRANSFORM -> EMIT pattern:
---  - INITIALIZE: Not needed (queries spec_objects at emit time)
---  - TRANSFORM: Not needed (queries spec_objects at emit time)
---  - EMIT: Query spec_objects, return Pandoc Div with BulletList
---
---@module toc
local M = {}

M.view = {
    id = "TOC",
    long_name = "Table of Contents",
    description = "Document table of contents",
    inline_prefix = "toc",
}

-- ============================================================================
-- Parsing
-- ============================================================================

---Parse TOC parameters from syntax.
---@param text string Parameter text after "toc:"
---@return table params Parsed parameters {depth = number|nil}
local function parse_params(text)
    local params = {}
    if not text or text == "" then
        return params
    end

    -- Parse key=value pairs
    for key, value in text:gmatch("(%w+)%s*=%s*(%S+)") do
        if key == "depth" or key == "max_level" then
            params.depth = tonumber(value)
        end
    end

    return params
end

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_toc_code = prefix_matcher.from_decl(M.view)
local match_toc_codeblock = prefix_matcher.codeblock_from_decl(M.view)

-- ============================================================================
-- Data Generation
-- ============================================================================

---Generate TOC data by querying spec_objects.
---@param params table Parameters {depth = number|nil}
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return table entries Array of {level, pid, title, anchor}
function M.generate(params, data, spec_id)
    params = params or {}
    local max_depth = params.depth

    local rows = data:query_all([[
        SELECT o.id, o.level, o.pid, o.title_text, o.label
        FROM spec_objects o
        WHERE o.specification_ref = :spec_id
        ORDER BY o.file_seq
    ]], { spec_id = spec_id })

    local entries = {}
    for _, row in ipairs(rows or {}) do
        local level = row.level or 2
        if not max_depth or level <= max_depth + 1 then
            table.insert(entries, {
                level = level,
                pid = row.pid,
                title = row.title_text or row.pid or "Untitled",
                anchor = row.label or row.id
            })
        end
    end

    return entries
end

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "toc_handler",
    prerequisites = {"spec_objects"},  -- Needs objects to be populated

    ---EMIT: Render inline Code elements with toc: syntax.
    ---NOTE: TOC generates block-level content (BulletList), so inline Code
    ---cannot be replaced directly. Return nil to keep original or use CodeBlock.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Inline elements (placeholder) or nil
    on_render_Code = function(code, ctx)
        local rest = match_toc_code(code.text or "")
        if rest == nil then return nil end

        -- TOC generates block content - inline Code cannot be replaced with blocks.
        -- Return a placeholder or nil to keep the original code element.
        -- Use ``` toc: ``` code block syntax for actual TOC rendering.
        return { pandoc.Str("[TOC]") }
    end,

    ---EMIT: Render CodeBlock elements with toc class.
    ---Wraps output in a speccompiler-toc Div so format-specific filters
    ---(e.g., DOCX) can convert it to a native TOC field.
    ---The BulletList inside serves as fallback for formats without special handling.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx Context
    ---@return table|nil Replacement block
    on_render_CodeBlock = function(block, ctx)
        local rest = match_toc_codeblock(block)
        if not rest then return nil end

        local params = parse_params(rest)
        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if not data or not pandoc then
            return nil
        end

        local entries = M.generate(params, data, spec_id)
        if #entries == 0 then
            return pandoc.Para{pandoc.Str("[No entries for TOC]")}
        end

        -- Build Pandoc BulletList (fallback for non-DOCX formats)
        local items = {}
        for _, entry in ipairs(entries) do
            local text = entry.title
            if entry.pid then
                text = entry.pid .. ": " .. text
            end
            local link = pandoc.Link({pandoc.Str(text)}, "#" .. entry.anchor)
            table.insert(items, {pandoc.Plain{link}})
        end

        -- Wrap in Div for format-specific handling by filters
        local depth = params.depth or 3
        return pandoc.Div(
            {pandoc.BulletList(items)},
            pandoc.Attr("", {"speccompiler-toc"}, {["data-depth"] = tostring(depth)})
        )
    end
}

return M
