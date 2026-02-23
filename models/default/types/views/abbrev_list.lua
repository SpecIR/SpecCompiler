---Abbreviation List view type module.
---Handles `abbrev_list:` inline code syntax for generating abbreviation lists.
---
---Syntax:
---  `abbrev_list:`              - Full list of all abbreviations
---  `sigla_list:`               - Alias for abbrev_list:
---
---Queries spec_views for ABBREV entries and generates a sorted list.
---
---Uses the unified INITIALIZE -> TRANSFORM -> EMIT pattern:
---  - INITIALIZE: Not needed (queries ABBREV views at emit time)
---  - TRANSFORM: Not needed (queries ABBREV views at emit time)
---  - EMIT: Query spec_views/ABBREV, return Pandoc Table or BulletList
---
---@module abbrev_list
local M = {}

local Queries = require("db.queries")

M.view = {
    id = "ABBREV_LIST",
    long_name = "Abbreviation List",
    description = "List of all abbreviations defined in the document",
    inline_prefix = "abbrev_list",
    aliases = { "sigla_list", "acronym_list" },
}

-- ============================================================================
-- Parsing
-- ============================================================================

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_prefix = prefix_matcher.from_decl(M.view)
local match_abbrev_list_codeblock = prefix_matcher.codeblock_from_decl(M.view)
local function match_abbrev_list_code(text)
    return match_prefix(text) ~= nil
end

-- ============================================================================
-- Data Generation
-- ============================================================================

---Generate sorted abbreviation list from database.
---Queries spec_views for ABBREV entries.
---@param params table Parameters (unused)
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return table entries Array of {abbrev, meaning} sorted alphabetically
function M.generate(params, data, spec_id)
    local abbrevs = data:query_all(Queries.content.views_by_type, {
        spec_id = spec_id,
        view_type = "ABBREV"
    })

    local parsed = {}
    local seen = {}

    for _, row in ipairs(abbrevs or {}) do
        local json = row.raw_ast or ""
        local abbrev = json:match('"abbrev"%s*:%s*"([^"]*)"')
        local meaning = json:match('"meaning"%s*:%s*"([^"]*)"')

        if abbrev and meaning and not seen[abbrev] then
            table.insert(parsed, {
                abbrev = abbrev,
                meaning = meaning
            })
            seen[abbrev] = true
        end
    end

    -- Sort alphabetically by abbreviation
    table.sort(parsed, function(a, b)
        return a.abbrev:upper() < b.abbrev:upper()
    end)

    return parsed
end

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "abbrev_list_handler",
    prerequisites = {"abbrev_handler"},  -- Needs ABBREV views to be populated

    ---EMIT: Render inline Code elements with abbrev_list: syntax.
    ---NOTE: Abbreviation list generates block-level content (Table), so inline Code
    ---cannot be replaced directly. Return placeholder or use CodeBlock.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Inline elements (placeholder) or nil
    on_render_Code = function(code, ctx)
        if not match_abbrev_list_code(code.text or "") then
            return nil
        end

        -- Abbreviation list generates block content - inline Code cannot be replaced with blocks.
        -- Return a placeholder or nil to keep the original code element.
        -- Use ``` abbrev_list: ``` code block syntax for actual list rendering.
        return { pandoc.Str("[ABBREVIATION LIST]") }
    end,

    ---EMIT: Render CodeBlock elements with abbrev_list class.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx Context
    ---@return table|nil Replacement block
    on_render_CodeBlock = function(block, ctx)
        if not match_abbrev_list_codeblock(block) then return nil end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if not data or not pandoc then
            return nil
        end

        local entries = M.generate({}, data, spec_id)
        if #entries == 0 then
            return pandoc.Para{pandoc.Str("[No abbreviations defined]")}
        end

        -- Build rows as pandoc.Row objects with pandoc.Cell objects
        local rows = {}
        for _, entry in ipairs(entries) do
            table.insert(rows, pandoc.Row({
                pandoc.Cell({pandoc.Plain{pandoc.Strong{pandoc.Str(entry.abbrev)}}}),
                pandoc.Cell({pandoc.Plain{pandoc.Str(entry.meaning)}})
            }))
        end

        -- Create table with two columns (TableBody is a plain Lua table)
        local table_body = {
            attr = pandoc.Attr(),
            body = rows,
            head = {},
            row_head_columns = 0
        }
        local colspecs = {
            {pandoc.AlignLeft, nil},
            {pandoc.AlignLeft, nil}
        }

        return pandoc.Table(
            {long = {}, short = {}},
            colspecs,
            pandoc.TableHead{},
            {table_body},
            pandoc.TableFoot{}
        )
    end
}

return M
