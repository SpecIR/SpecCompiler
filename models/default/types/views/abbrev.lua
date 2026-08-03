---Abbreviation view type module.
---Handles `abbrev: Full Meaning (ABBR)` inline code syntax.
---
---Syntax:
---  `abbrev: National Aeronautics (NASA)`  - Define and render abbreviation
---  `sigla: National Aeronautics (NASA)`   - Alias for abbrev:
---  `acronym: National Aeronautics (NASA)` - Alias for abbrev:
---
---Uses the unified INITIALIZE -> EMIT pattern:
---  - INITIALIZE: Parse inline codes, store JSON in spec_views.raw_ast
---    (consumed by abbrev_list to build the abbreviation list)
---  - EMIT: Render the "Meaning (ABBR)" inlines live from the element text
---
---@module abbrev

local Queries = require("db.queries")

local schema = {
    id = "ABBREV",
    long_name = "Abbreviation",
    description = "Abbreviations/acronyms with first-use expansion",
    aliases = { "sigla", "acronym" },
    inline_prefix = "abbrev",
}

-- ============================================================================
-- Parsing
-- ============================================================================

---Parse abbreviation syntax: "Full Meaning Text (ABBREV)"
---@param text string Input text
---@return string|nil meaning Full meaning text
---@return string|nil abbrev Abbreviation
local function parse_abbrev(text)
    if not text or text == '' then
        return nil, nil
    end

    -- Pattern: "Full Meaning Text (ABBREV)"
    local meaning, abbrev = text:match('^(.-)%s*%(([^)]+)%)%s*$')

    if meaning and abbrev and meaning ~= '' and abbrev ~= '' then
        meaning = meaning:match('^%s*(.-)%s*$')
        abbrev = abbrev:match('^%s*(.-)%s*$')
        return meaning, abbrev
    end

    return nil, nil
end

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_abbrev_code = prefix_matcher.from_decl(schema, { require_content = true })

-- ============================================================================
-- Phase handler
-- ============================================================================

---Initialize phase: Extract abbreviation definitions from inline code.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
local function on_initialize(data, contexts, diagnostics)
    for _, ctx in ipairs(contexts) do
        local doc = ctx.doc
        if not doc or not doc.blocks then goto continue end

        local spec_id = ctx.spec_id or "default"
        local file_seq = 0
        local abbrevs_found = {}

        local visitor = {
            Code = function(c)
                local content = match_abbrev_code(c.text or "")
                if not content then return nil end

                local meaning, abbrev = parse_abbrev(content)
                if meaning and abbrev then
                    file_seq = file_seq + 1
                    table.insert(abbrevs_found, {
                        meaning = meaning,
                        abbrev = abbrev,
                        file_seq = file_seq,
                        from_file = ctx.source_path or "unknown"
                    })
                else
                    if diagnostics and diagnostics.add_warning then
                        diagnostics:add_warning(
                            string.format('Invalid abbrev syntax: "%s" (expected "Meaning (ABBR)")', content),
                            ctx.source_path
                        )
                    end
                end
            end
        }

        for _, block in ipairs(doc.blocks) do
            pandoc.walk_block(block, visitor)
        end

        -- Store abbreviations in database
        for _, a in ipairs(abbrevs_found) do
            local content_key = spec_id .. ":" .. a.abbrev .. ":" .. a.meaning
            local identifier = pandoc.sha1(content_key)

            local json_content = string.format(
                '{"abbrev":"%s","meaning":"%s"}',
                a.abbrev:gsub('"', '\\"'),
                a.meaning:gsub('"', '\\"')
            )

            data:execute(Queries.content.insert_view, {
                identifier = identifier,
                specification_ref = spec_id,
                view_type_ref = "ABBREV",
                from_file = a.from_file,
                file_seq = a.file_seq,
                raw_ast = json_content
            })
        end

        if #abbrevs_found > 0 and diagnostics and diagnostics.add_info then
            diagnostics:add_info(string.format("Found %d abbreviation definitions", #abbrevs_found))
        end

        ::continue::
    end
end

-- ============================================================================
-- Render
-- ============================================================================

---EMIT: Render inline Code elements with abbreviation syntax.
---The output is a pure function of the element text, so it renders live --
---no precomputed AST round-trip through the database.
---@param ctx Context
---@return table|nil Replacement inlines
local function render(ctx)
    local code = ctx.subject.element
    local content = match_abbrev_code(code.text or "")
    if not content then return nil end

    local meaning, abbrev = parse_abbrev(content)
    if not meaning or not abbrev then
        return nil
    end

    -- First occurrence format: "Full Meaning (ABBR)"
    local output_text = meaning .. " (" .. abbrev .. ")"
    return { pandoc.Str(output_text) }
end

-- Phase ordering: must run AFTER spec_views clears old views
schema.phase_prerequisites = { "spec_views" }

return {
    kind = "view",
    schema = schema,
    hooks = {
        render = render,
        on_initialize = on_initialize,
    },
}
