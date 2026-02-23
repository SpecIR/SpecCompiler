---Cross-reference relation type for citations.
---Targets: Bibliography entries via @cite/@citep selectors.
---
---@module xref_citation
local M = {}
local Queries = require("db.queries")
local ast_utils = require("pipeline.shared.ast_utils")

M.relation = {
    id = "XREF_CITATION",
    long_name = "Citation Reference",
    description = "Cross-reference to a bibliography entry",

    -- Inference pattern (source, attribute, target)
    source_type_ref = nil,     -- nil = any source can cite
    source_attribute = nil,    -- nil = any attribute
    target_type_ref = nil,     -- Citations target bibliography entries, not spec objects

    -- Resolution
    link_selector = "@cite,@citep",
}

-- ============================================================================
-- Handler
-- ============================================================================

---Rewrite citation links to pandoc.Cite elements.
---@param data DataManager
---@param spec_id string Specification identifier
local function rewrite_citation_links(data, spec_id)
    if not pandoc then return end

    local objects = data:query_all(Queries.content.objects_with_ast, {
        spec_id = spec_id
    })

    for _, obj in ipairs(objects or {}) do
        local decoded = pandoc.json.decode(obj.ast)
        if not decoded then goto continue end

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
            local new_ast = pandoc.json.encode(temp_doc.blocks)
            data:execute(Queries.content.update_object_ast, {
                id = obj.id,
                ast = new_ast
            })
        end

        ::continue::
    end
end

M.handler = {
    name = "xref_citation_handler",
    prerequisites = {"spec_relations"},  -- Run after relations are stored

    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local spec_id = ctx.spec_id or "default"
            rewrite_citation_links(data, spec_id)
        end
    end
}

return M
