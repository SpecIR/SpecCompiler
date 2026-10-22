---Relation Link Rewriter Handler for SpecCompiler.
---Pipeline handler for TRANSFORM phase.
---
---Rewrites links in stored AST using resolved relation data from RESOLVE phase.
---Uses the relation lookup (keyed by source_object_id + selector + target_text)
---to correctly rewrite scoped references to the right target anchor and display text.
---
---@module relation_link_rewriter
local Queries = require("db.queries")
local ast_utils = require("pipeline.shared.ast_utils")
local relation_lookup = require("pipeline.shared.relation_lookup")

local M = {
    name = "relation_link_rewriter",
    prerequisites = { "float_numbering", "spec_floats_transform" }
}

---Rewrite links in stored ASTs using resolved relation data.
---Uses the relation lookup (keyed by source id + selector + target_text) to
---rewrite scoped references to the right target anchor and display text. The
---same walk serves spec_objects (source id = row id) and spec_attribute_values
---(source id = owner_object_id); only the queries and id field differ.
---@param data DataManager
---@param spec_id string Specification identifier
---@param lookup table Map of "source_id|selector|target_text" -> {spec, anchor, display_text}
---@param select_query string Query returning rows with {id, ast, [source_id_field]}
---@param source_id_field string Row field holding the link source object id
---@param update_query string UPDATE statement taking {id, ast}
local function rewrite_links(data, spec_id, lookup, select_query, source_id_field, update_query)
    if not pandoc then return end

    local rows = data:query_all(select_query, { spec_id = spec_id })

    for _, row in ipairs(rows or {}) do
        local decoded = pandoc.json.decode(row.ast)
        if decoded then
            local original_is_single_block = decoded.t ~= nil
            local blocks = ast_utils.extract_blocks(decoded)

            if blocks and #blocks > 0 then
                -- Wrap in temp doc for walking
                local temp_doc = pandoc.Pandoc(blocks)

                local modified = false

                -- Create link rewriting filter using relation-aware lookup
                local link_filter = {
                    Link = function(link)
                        local target = link.target or ""
                        local content_text = pandoc.utils.stringify(link.content)

                        if target:match("^[@#]") then
                            -- Look up by (source id, selector, target_text)
                            local resolved = relation_lookup.find(lookup, row[source_id_field], target, content_text)

                            if resolved then
                                link.target = relation_lookup.link_target(resolved, spec_id)
                                if resolved.display_text then
                                    link.content = { pandoc.Str(resolved.display_text) }
                                end
                                modified = true
                                return link
                            end
                            -- Fallback only for base selectors;
                            -- extended selectors left for type-specific handlers
                            local fallback = relation_lookup.fallback_target(target, content_text)
                            if fallback then
                                link.target = fallback
                                modified = true
                                return link
                            end
                        end

                        return link
                    end
                }

                -- Apply filter
                temp_doc = temp_doc:walk(link_filter)

                -- If modified, update the stored AST
                if modified then
                    local payload = original_is_single_block and temp_doc.blocks[1] or temp_doc.blocks
                    local new_ast = pandoc.json.encode(payload)
                    data:execute(update_query, { id = row.id, ast = new_ast })
                end
            end
        end
    end
end

---Rewrite links in stored AST using resolved anchors.
---Resolution is handled by relation_resolver in RESOLVE phase.
function M.on_transform(data, contexts, diagnostics)
    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        local lookup = relation_lookup.build(data, spec_id, ctx, diagnostics)
        rewrite_links(data, spec_id, lookup,
            Queries.content.objects_with_ast, "id", Queries.content.update_object_ast)
        rewrite_links(data, spec_id, lookup,
            Queries.content.attributes_with_ast, "owner_object_id", Queries.content.update_attribute_ast)
        rewrite_links(data, spec_id, lookup,
            [[
                SELECT id, parent_object_id, resolved_ast AS ast
                FROM spec_floats
                WHERE specification_ref = :spec_id
                  AND resolved_ast IS NOT NULL
                  AND parent_object_id IS NOT NULL
            ]],
            "parent_object_id",
            [[ UPDATE spec_floats SET resolved_ast = :ast WHERE id = :id ]])
    end
    data:commit()
end

return M
