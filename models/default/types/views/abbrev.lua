---Abbreviation view type module.
---Handles `abbrev: Full Meaning (ABBR)` inline code syntax.
---
---Syntax:
---  `abbrev: National Aeronautics (NASA)`  - Define and render abbreviation
---  `sigla: National Aeronautics (NASA)`   - Alias for abbrev:
---  `acronym: National Aeronautics (NASA)` - Alias for abbrev:
---
---Uses the unified INITIALIZE -> TRANSFORM -> EMIT pattern:
---  - INITIALIZE: Parse inline codes, store JSON in spec_views.raw_ast
---  - TRANSFORM: Convert raw_ast -> Pandoc JSON -> resolved_ast
---  - EMIT: Look up resolved_ast, return Pandoc element
---
---@module abbrev
local M = {}

local view_utils = require("pipeline.shared.view_utils")
local Queries = require("db.queries")

M.view = {
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
local match_abbrev_code = prefix_matcher.from_decl(M.view, { require_content = true })

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "abbrev_handler",
    prerequisites = {"spec_views"},  -- Must run AFTER spec_views clears old views

    ---Initialize phase: Extract abbreviation definitions from inline code.
    ---@param data DataManager
    ---@param contexts Context[]
    ---@param diagnostics Diagnostics
    on_initialize = function(data, contexts, diagnostics)
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
    end,

    ---TRANSFORM: Convert raw_ast to Pandoc JSON, store in resolved_ast
    ---@param data DataManager
    ---@param contexts Context[]
    ---@param diagnostics Diagnostics
    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local spec_id = ctx.spec_id or "default"

            -- Query abbrev views needing conversion
            local views = data:query_all(Queries.content.views_needing_transform, {
                spec_id = spec_id,
                view_type = "ABBREV"
            })

            for _, view in ipairs(views or {}) do
                local json = view.raw_ast or ""
                local abbrev = json:match('"abbrev"%s*:%s*"([^"]*)"')
                local meaning = json:match('"meaning"%s*:%s*"([^"]*)"')

                if abbrev and meaning then
                    -- First occurrence format: "Full Meaning (ABBR)"
                    local output_text = meaning .. " (" .. abbrev .. ")"

                    -- Convert to Pandoc JSON
                    local str = pandoc.Str(output_text)
                    local resolved = view_utils.to_pandoc_json(str)
                    if resolved then
                        data:execute(Queries.content.update_view_resolved, {
                            id = view.id,
                            resolved = resolved
                        })
                    end
                end
            end
        end
    end,

    ---EMIT: Render inline Code elements with abbreviation syntax.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Replacement inlines
    on_render_Code = function(code, ctx)
        local content = match_abbrev_code(code.text or "")
        if not content then return nil end

        local meaning, abbrev = parse_abbrev(content)
        if not meaning or not abbrev then
            return nil
        end

        -- Look up resolved_ast from database
        local spec_id = ctx.spec_id or "default"
        local data = ctx.data
        if data then
            -- Build the raw_ast JSON to match
            local raw_json = string.format(
                '{"abbrev":"%s","meaning":"%s"}',
                abbrev:gsub('"', '\\"'),
                meaning:gsub('"', '\\"')
            )
            local resolved = view_utils.lookup_resolved_ast(data, spec_id, "ABBREV", raw_json)
            if resolved then
                local doc = view_utils.from_pandoc_json(resolved)
                if doc and doc.blocks and #doc.blocks > 0 then
                    local block = doc.blocks[1]
                    if block.content then
                        return block.content
                    end
                end
            end
        end

        -- Fallback: generate directly if no resolved_ast
        local output_text = meaning .. " (" .. abbrev .. ")"
        return { pandoc.Str(output_text) }
    end
}

-- ============================================================================
-- List Generation (for sigla_list:)
-- ============================================================================

---Get sorted abbreviation list from database.
---@param data DataManager
---@param spec_id string Specification identifier
---@return table rows Array of {abbrev, meaning} sorted alphabetically
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

---Generate OOXML table for abbreviation list.
---@param data DataManager
---@param spec_id string Specification identifier
---@return string OOXML table content
function M.generate_list_ooxml(data, spec_id)
    local abbrevs = M.get_list(data, spec_id)

    if #abbrevs == 0 then
        return '<w:p><w:r><w:t>No abbreviations defined.</w:t></w:r></w:p>'
    end

    -- Build clean list-style OOXML (no table borders, no header)
    -- Format: "ABBR    Full meaning text" with tab separator
    local parts = {}

    for _, a in ipairs(abbrevs) do
        -- Each abbreviation as a paragraph with tab-separated columns
        -- Using custom tab stops for alignment
        table.insert(parts, string.format([[<w:p>
<w:pPr>
<w:tabs><w:tab w:val="left" w:pos="1701"/></w:tabs>
<w:spacing w:after="120" w:line="240" w:lineRule="auto"/>
</w:pPr>
<w:r><w:t>%s</w:t></w:r>
<w:r><w:tab/></w:r>
<w:r><w:t>%s</w:t></w:r>
</w:p>]], a.abbrev, a.meaning))
    end

    return table.concat(parts, "\n")
end

return M
