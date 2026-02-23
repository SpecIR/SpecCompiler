---List of Floats view type module.
---Handles `lof:` and `lot:` inline code syntax for generating float lists.
---
---Syntax:
---  `lof:`                    - List of Figures (counter_group=FIGURE)
---  `lof: counter_group=TABLE` - List of Tables
---  `lot:`                    - Alias for lof: counter_group=TABLE
---
---Uses the unified INITIALIZE -> TRANSFORM -> EMIT pattern:
---  - INITIALIZE: Not needed (queries spec_floats at emit time)
---  - TRANSFORM: Not needed (queries spec_floats at emit time)
---  - EMIT: Query spec_floats by counter_group, return Pandoc BulletList
---
---@module lof
local M = {}

M.view = {
    id = "LOF",
    long_name = "List of Floats",
    description = "List of figures, tables, or other floats",
    inline_prefix = "lof",
    aliases = { "lot" },  -- lot: is alias with counter_group=TABLE
}

-- ============================================================================
-- Parsing
-- ============================================================================

---Parse LOF parameters from syntax.
---@param text string Parameter text after "lof:"
---@return table params Parsed parameters {counter_group = string}
local function parse_params(text)
    local params = {}
    if not text or text == "" then
        return params
    end

    -- Parse key=value pairs
    for key, value in text:gmatch("(%w+)%s*=%s*(%S+)") do
        if key == "counter_group" or key == "type" or key == "group" then
            params.counter_group = value:upper()
        end
    end

    return params
end

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_lof_code = prefix_matcher.from_decl(M.view)
local match_lof_codeblock = prefix_matcher.codeblock_from_decl(M.view)

-- ============================================================================
-- Data Generation
-- ============================================================================

---Generate float list data by querying spec_floats.
---@param params table Parameters {counter_group = string}
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return table entries Array of {number, label, caption, anchor, type}
function M.generate(params, data, spec_id)
    params = params or {}
    local counter_group = params.counter_group or "FIGURE"

    local rows = data:query_all([[
        SELECT f.id, f.label, f.caption, f.number, f.anchor, f.type_ref,
               t.caption_format
        FROM spec_floats f
        JOIN spec_float_types t ON f.type_ref = t.identifier
        WHERE f.specification_ref = :spec_id
          AND t.counter_group = :counter_group
        ORDER BY f.file_seq
    ]], { spec_id = spec_id, counter_group = counter_group })

    local entries = {}
    for _, row in ipairs(rows or {}) do
        local caption_text = row.caption or row.label or "Untitled"
        local number_text = ""
        if row.caption_format and row.number then
            number_text = row.caption_format .. " " .. row.number .. " - "
        elseif row.number then
            number_text = "Figure " .. row.number .. " - "
        end

        table.insert(entries, {
            number = row.number,
            label = row.label,
            caption = caption_text,
            display = number_text .. caption_text,
            anchor = row.anchor or row.label or tostring(row.id),
            type = row.type_ref
        })
    end

    return entries
end

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "lof_handler",
    prerequisites = {"spec_floats"},  -- Needs floats to be populated

    ---EMIT: Render inline Code elements with lof:/lot: syntax.
    ---NOTE: LOF/LOT generates block-level content (BulletList), so inline Code
    ---cannot be replaced directly. Return nil to keep original or use CodeBlock.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Inline elements (placeholder) or nil
    on_render_Code = function(code, ctx)
        local rest, prefix = match_lof_code(code.text or "")
        if rest == nil then return nil end

        -- LOF/LOT generates block content - inline Code cannot be replaced with blocks.
        -- Return a placeholder or nil to keep the original code element.
        -- Use ``` lof: ``` or ``` lot: ``` code block syntax for actual list rendering.
        local placeholder = prefix == "lot" and "[LOT]" or "[LOF]"
        return { pandoc.Str(placeholder) }
    end,

    ---EMIT: Render CodeBlock elements with lof/lot class.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx Context
    ---@return table|nil Replacement block
    on_render_CodeBlock = function(block, ctx)
        local rest, prefix = match_lof_codeblock(block)
        if not prefix then return nil end

        local params = parse_params(rest)

        -- lot: defaults to TABLE counter_group
        if prefix == "lot" and not params.counter_group then
            params.counter_group = "TABLE"
        end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if not data or not pandoc then
            return nil
        end

        local entries = M.generate(params, data, spec_id)
        if #entries == 0 then
            local group = params.counter_group or "FIGURE"
            return pandoc.Para{pandoc.Str("[No " .. group:lower() .. "s found]")}
        end

        -- Build Pandoc BulletList
        local items = {}
        for _, entry in ipairs(entries) do
            local link = pandoc.Link({pandoc.Str(entry.display)}, "#" .. entry.anchor)
            table.insert(items, {pandoc.Plain{link}})
        end

        return pandoc.BulletList(items)
    end
}

return M
