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

local Queries = require("db.queries")

local schema = {
    id = "ABBREV_LIST",
    long_name = "Abbreviation List",
    description = "List of all abbreviations defined in the document",
    inline_prefix = "abbrev_list",
    aliases = { "sigla_list", "acronym_list" },
    materializer_type = "abbrev_list",
    view_subtype_ref = "ABBREV",
}

-- ============================================================================
-- Parsing
-- ============================================================================

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_prefix = prefix_matcher.from_decl(schema)
local match_abbrev_list_codeblock = prefix_matcher.codeblock_from_decl(schema)
local function match_abbrev_list_code(text)
    return match_prefix(text) ~= nil
end

-- ============================================================================
-- Data Generation
-- ============================================================================

---Get sorted abbreviation list from database.
---Queries spec_views for ABBREV entries.
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return table entries Array of {abbrev, meaning} sorted alphabetically
local function get_list(data, spec_id)
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
-- OOXML Generation
-- ============================================================================

---Build the abbreviation list as a SEMANTIC Pandoc table (two columns:
---Abbreviation | Description). Format-specific styling is left to the filters --
---no model hardcodes OOXML here. Shared by `render_block` (inline ```abbrev_list:```
---blocks) and `build_block` (cross-model reuse, e.g. the ABNT "Lista de Siglas").
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return table|nil block A pandoc.Table, an empty-state Para, or nil
local function build_abbrev_block(data, spec_id)
    if not data or not pandoc then return nil end

    local entries = get_list(data, spec_id)
    if #entries == 0 then
        return pandoc.Para{pandoc.Str("[No abbreviations defined]")}
    end

    local rows = {}
    for _, entry in ipairs(entries) do
        table.insert(rows, pandoc.Row({
            pandoc.Cell({pandoc.Plain{pandoc.Strong{pandoc.Str(entry.abbrev)}}}),
            pandoc.Cell({pandoc.Plain{pandoc.Str(entry.meaning)}})
        }))
    end

    local table_body = { attr = pandoc.Attr(), body = rows, head = {}, row_head_columns = 0 }
    local colspecs = { {pandoc.AlignLeft, nil}, {pandoc.AlignLeft, nil} }
    return pandoc.Table(
        {long = {}, short = {}}, colspecs,
        pandoc.TableHead{}, {table_body}, pandoc.TableFoot{}
    )
end

-- ============================================================================
-- Descriptor
-- ============================================================================

return {
    kind = "view",
    schema = schema,
    hooks = {
        ---EMIT: Render inline Code elements with abbrev_list: syntax.
        ---NOTE: Abbreviation list generates block-level content (Table), so inline Code
        ---cannot be replaced directly. Return placeholder or use CodeBlock.
        ---@param code table Pandoc Code element
        ---@param ctx Context
        ---@return table|nil Inline elements (placeholder) or nil
        render = function(ctx)
            local code = ctx.subject.element
            if not match_abbrev_list_code(code.text or "") then
                return nil
            end

            local data = ctx.data
            local spec_id = ctx.spec_id or "default"

            if data then
                local entries = get_list(data, spec_id)
                if #entries == 0 then
                    return { pandoc.Str("[No abbreviations defined]") }
                end
            end

            -- Non-empty abbreviation list generates block content (Table).
            -- Inline Code cannot be replaced with blocks.
            -- Use ``` abbrev_list: ``` code block syntax for actual list rendering.
            return { pandoc.Str("[ABBREVIATION LIST]") }
        end,

        ---EMIT: Render CodeBlock elements with abbrev_list class.
        ---@param block table Pandoc CodeBlock element
        ---@param ctx Context
        ---@return table|nil Replacement block
        render_block = function(ctx)
            if not match_abbrev_list_codeblock(ctx.subject.element) then return nil end
            return build_abbrev_block(ctx.data, ctx.spec_id or "default")
        end,

        ---DATA: produce the abbreviation list as a semantic pandoc.Table.
        ---Host-dispatched (get_hook("view","ABBREV_LIST","build_block")) so other
        ---models render an ABNT-style "Lista de Siglas" via the host instead of a
        ---file-path require. dctx.subject.params is unused.
        ---@param dctx table frozen data context (dctx.data, dctx.spec_id)
        ---@return table|nil block A pandoc.Table (or empty-state Para)
        build_block = function(dctx)
            return build_abbrev_block(dctx.data, dctx.spec_id or "default")
        end,
    },
}
