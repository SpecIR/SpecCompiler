---Cross-reference relation type for citations.
---Targets: Bibliography entries via @cite/@citep selectors.
---
---@module xref_citation
local Queries = require("db.queries")
local ast_utils = require("pipeline.shared.ast_utils")

-- ============================================================================
-- Handler
-- ============================================================================

local function rewrite_citation_rows(data, rows, update_query)
    if not pandoc then return end

    for _, row in ipairs(rows or {}) do
        local decoded = pandoc.json.decode(row.ast)
        if not decoded then goto continue end

        local original_is_single_block = decoded.t ~= nil
        local blocks = ast_utils.extract_blocks(decoded)
        if not blocks or #blocks == 0 then goto continue end

        local temp_doc = pandoc.Pandoc(blocks)
        local modified = false

        temp_doc = temp_doc:walk({
            Link = function(link)
                local target = link.target or ""
                if target ~= "@cite" and target ~= "@citep" then
                    return link
                end

                local keys = pandoc.utils.stringify(link.content)
                if not keys or keys == "" then
                    return link
                end

                -- Create pandoc.Cite element
                local mode = (target == "@citep") and "AuthorInText" or "NormalCitation"
                local citations = {}
                for key in keys:gmatch("[^;]+") do
                    key = key:match("^%s*(.-)%s*$")  -- trim whitespace
                    -- Create Citation with positional args: (id, mode)
                    local citation = pandoc.Citation(key, mode)
                    table.insert(citations, citation)
                end

                modified = true
                return pandoc.Cite({pandoc.Str("[" .. keys .. "]")}, citations)
            end
        })

        if modified then
            local payload = original_is_single_block and temp_doc.blocks[1] or temp_doc.blocks
            local new_ast = pandoc.json.encode(payload)
            data:execute(update_query, { id = row.id, ast = new_ast })
        end

        ::continue::
    end
end

---Rewrite citation links to pandoc.Cite elements.
---@param data DataManager
---@param spec_id string Specification identifier
local function rewrite_citation_links(data, spec_id)
    rewrite_citation_rows(
        data,
        data:query_all(Queries.content.objects_with_ast, { spec_id = spec_id }),
        Queries.content.update_object_ast
    )

    rewrite_citation_rows(
        data,
        data:query_all([[
            SELECT id, resolved_ast AS ast
            FROM spec_floats
            WHERE specification_ref = :spec_id
              AND resolved_ast IS NOT NULL
        ]], { spec_id = spec_id }),
        [[ UPDATE spec_floats SET resolved_ast = :ast WHERE id = :id ]]
    )
end

return {
    kind = "relation",
    schema = {
        id = "XREF_CITATION",
        long_name = "Citation Reference",
        description = "Cross-reference to a bibliography entry",

        -- Inference pattern (source, attribute, target)
        source_type_ref = nil,     -- nil = any source can cite
        source_attribute = nil,    -- nil = any attribute
        target_type_ref = nil,     -- Citations target bibliography entries, not spec objects

        -- Resolution
        link_selector = "@cite,@citep",

        -- Phase ordering: run after table floats have a resolved AST to rewrite
        phase_prerequisites = { "spec_floats_transform" },
    },
    hooks = {
        on_transform = function(data, contexts, diagnostics)
            for _, ctx in ipairs(contexts) do
                local spec_id = ctx.spec_id or "default"
                rewrite_citation_links(data, spec_id)
            end
        end,
    },
}
