---Link rewrite utilities for SpecCompiler.
---Shared infrastructure for relation type on_transform handlers that need
---to customize link display text.  The heavy lifting lives here so that
---individual type handlers stay lean.
---
---@module link_rewrite_utils
local Queries = require("db.queries")
local ast_utils = require("pipeline.shared.ast_utils")

local M = {}

---Rewrite link display text for a specific relation type.
---Queries resolved relations, builds a per-source-object override map,
---walks affected ASTs, and updates them in the database.
---
---@param data DataManager
---@param contexts Context[]  Array of pipeline contexts (one per spec)
---@param type_ref string     Relation type to target (e.g., "XREF_DIC")
---@param display_fn function(target: table): string|nil  Returns custom display text or nil to skip
function M.rewrite_display_for_type(data, contexts, type_ref, display_fn)
    if not pandoc then return end

    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        -- 1. Query all resolved relations for this spec
        local relations = data:query_all(
            Queries.resolution.select_resolved_relations_with_targets,
            { spec_id = spec_id }
        )
        if not relations or #relations == 0 then goto next_ctx end

        -- 2. Filter for the target relation type and build override map
        --    overrides[source_object_id][link_target] = new_display_text
        local overrides = {}

        for _, r in ipairs(relations) do
            if r.relation_type_ref == type_ref and r.object_pid then
                local new_text = display_fn({
                    pid = r.object_pid,
                    type_ref = r.object_type_ref,
                    title_text = r.object_title_text
                })
                if new_text then
                    local src_id = r.source_object_id
                    if not overrides[src_id] then
                        overrides[src_id] = {}
                    end
                    -- Same-document anchor
                    overrides[src_id]["#" .. r.object_pid] = new_text
                    -- Cross-document anchor
                    if r.object_spec and r.object_spec ~= spec_id then
                        overrides[src_id][r.object_spec .. ".ext#" .. r.object_pid] = new_text
                    end
                end
            end
        end

        -- 3. Walk only objects that have overrides
        if not next(overrides) then goto next_ctx end

        local objects = data:query_all(
            Queries.content.objects_with_ast,
            { spec_id = spec_id }
        )

        for _, obj in ipairs(objects or {}) do
            local obj_overrides = overrides[obj.id]
            if not obj_overrides then goto next_obj end

            local decoded = pandoc.json.decode(obj.ast)
            local blocks = ast_utils.extract_blocks(decoded)
            if not blocks or #blocks == 0 then goto next_obj end

            local temp_doc = pandoc.Pandoc(blocks)
            local modified = false

            temp_doc = temp_doc:walk({
                Link = function(link)
                    local target = link.target or ""
                    local new_text = obj_overrides[target]
                    if new_text then
                        link.content = { pandoc.Str(new_text) }
                        modified = true
                        return link
                    end
                    return link
                end
            })

            if modified then
                local new_ast = pandoc.json.encode(temp_doc.blocks)
                data:execute(Queries.content.update_object_ast, {
                    id = obj.id,
                    ast = new_ast
                })
            end

            ::next_obj::
        end

        ::next_ctx::
    end
end

return M
