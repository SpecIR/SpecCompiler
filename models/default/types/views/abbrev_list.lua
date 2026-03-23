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
local xml = require("infra.format.xml")

M.view = {
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
local match_prefix = prefix_matcher.from_decl(M.view)
local match_abbrev_list_codeblock = prefix_matcher.codeblock_from_decl(M.view)
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
function M.get_list(data, spec_id)
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

---Generate OOXML table for abbreviation list.
---Produces a two-column table with header row (Abbreviation | Description).
---@param data DataManager Database instance
---@param spec_id string Specification identifier
---@return string OOXML content
function M.generate_list_ooxml(data, spec_id)
    local abbrevs = M.get_list(data, spec_id)

    if #abbrevs == 0 then
        local empty_p = xml.node("w:p", {}, {
            xml.node("w:r", {}, {
                xml.node("w:t", {}, { xml.text("No abbreviations defined.") })
            })
        })
        return xml.serialize_element(empty_p)
    end

    -- Build table rows
    local rows = {}

    -- Header row
    local header_row = xml.node("w:tr", {}, {
        xml.node("w:tc", {}, {
            xml.node("w:tcPr", {}, {
                xml.node("w:tcW", { ["w:type"] = "pct", ["w:w"] = "1500" }),
            }),
            xml.node("w:p", {}, {
                xml.node("w:pPr", {}, {
                    xml.node("w:spacing", { ["w:before"] = "40", ["w:after"] = "40" }),
                }),
                xml.node("w:r", {}, {
                    xml.node("w:rPr", {}, { xml.node("w:b") }),
                    xml.node("w:t", {}, { xml.text("Abbreviation") }),
                }),
            }),
        }),
        xml.node("w:tc", {}, {
            xml.node("w:tcPr", {}, {
                xml.node("w:tcW", { ["w:type"] = "pct", ["w:w"] = "3500" }),
            }),
            xml.node("w:p", {}, {
                xml.node("w:pPr", {}, {
                    xml.node("w:spacing", { ["w:before"] = "40", ["w:after"] = "40" }),
                }),
                xml.node("w:r", {}, {
                    xml.node("w:rPr", {}, { xml.node("w:b") }),
                    xml.node("w:t", {}, { xml.text("Description") }),
                }),
            }),
        }),
    })
    table.insert(rows, header_row)

    -- Data rows
    for _, a in ipairs(abbrevs) do
        local row = xml.node("w:tr", {}, {
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", { ["w:type"] = "pct", ["w:w"] = "1500" }),
                }),
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:spacing", { ["w:before"] = "20", ["w:after"] = "20" }),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:rPr", {}, { xml.node("w:b") }),
                        xml.node("w:t", {}, { xml.text(a.abbrev) }),
                    }),
                }),
            }),
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", { ["w:type"] = "pct", ["w:w"] = "3500" }),
                }),
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:spacing", { ["w:before"] = "20", ["w:after"] = "20" }),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:t", {}, { xml.text(a.meaning) }),
                    }),
                }),
            }),
        })
        table.insert(rows, row)
    end

    -- Assemble table children: tblPr + tblGrid + all rows
    local children = {
        xml.node("w:tblPr", {}, {
            xml.node("w:tblStyle", { ["w:val"] = "TableGrid" }),
            xml.node("w:tblW", { ["w:type"] = "pct", ["w:w"] = "5000" }),
            xml.node("w:tblLook", {
                ["w:val"] = "04A0",
                ["w:firstRow"] = "1",
                ["w:lastRow"] = "0",
                ["w:firstColumn"] = "0",
                ["w:lastColumn"] = "0",
                ["w:noHBand"] = "0",
                ["w:noVBand"] = "1",
            }),
        }),
        xml.node("w:tblGrid", {}, {
            xml.node("w:gridCol", { ["w:w"] = "2700" }),
            xml.node("w:gridCol", { ["w:w"] = "6656" }),
        }),
    }
    for _, row in ipairs(rows) do
        table.insert(children, row)
    end

    local tbl = xml.node("w:tbl", {}, children)

    return xml.serialize_element(tbl)
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

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if data then
            local entries = M.get_list(data, spec_id)
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
    on_render_CodeBlock = function(block, ctx)
        if not match_abbrev_list_codeblock(block) then return nil end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if not data or not pandoc then
            return nil
        end

        local entries = M.get_list(data, spec_id)
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
