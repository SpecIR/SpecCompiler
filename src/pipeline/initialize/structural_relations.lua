---Structural Relations Handler for SpecCompiler.
---Creates pre-resolved relations inferred from document hierarchy (header nesting).
---
---Structural relation types (is_structural=1) declare source_type_ref and target_type_ref.
---For each source object, the handler finds the nearest enclosing ancestor of the
---target type using line-range containment and inserts a fully resolved spec_relation.
---
---@module structural_relations
local logger = require("infra.logger")
local Queries = require("db.queries")
local hash_utils = require("infra.hash_utils")

local M = {
    name = "structural_relations",
    prerequisites = {"spec_objects"}
}

---BATCH MODE: Process ALL documents in a single transaction.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    -- Load structural relation type definitions
    local structural_types = data:query_all(Queries.resolution.structural_relation_types)

    if not structural_types or #structural_types == 0 then
        return
    end

    -- Collect unique spec IDs from contexts
    local spec_ids_seen = {}
    local spec_ids = {}
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"
        if not spec_ids_seen[spec_id] then
            spec_ids_seen[spec_id] = true
            table.insert(spec_ids, spec_id)
        end
    end

    local total_count = 0

    data:begin_transaction()

    for _, spec_id in ipairs(spec_ids) do
        for _, rel_type in ipairs(structural_types) do
            if not rel_type.source_type_ref or not rel_type.target_type_ref then
                goto continue_type
            end

            -- Find all source objects of the declared source type
            local sources = data:query_all(Queries.resolution.objects_by_spec_and_type, {
                spec_id = spec_id,
                source_type = rel_type.source_type_ref
            })

            for _, source in ipairs(sources or {}) do
                -- Find nearest ancestor of the target type
                local ancestor = data:query_one(Queries.resolution.find_structural_ancestor, {
                    spec_id = spec_id,
                    from_file = source.from_file,
                    start_line = source.start_line,
                    level = source.level,
                    target_type = rel_type.target_type_ref
                })

                if ancestor then
                    local content_key = spec_id .. "|" .. source.id .. "|" .. ancestor.id .. "|" .. rel_type.identifier
                    local content_sha = hash_utils.sha1(content_key)

                    data:execute(Queries.resolution.insert_relation, {
                        content_sha = content_sha,
                        specification_ref = spec_id,
                        source_object_id = source.id,
                        target_text = nil,
                        target_object_id = ancestor.id,
                        target_float_id = nil,
                        type_ref = rel_type.identifier,
                        from_file = source.from_file,
                        link_line = source.start_line or 0,
                        source_attribute = nil,
                        link_selector = "^"
                    })
                    total_count = total_count + 1
                end
            end

            ::continue_type::
        end
    end

    data:commit()

    if total_count > 0 then
        logger.info(string.format("Created %d structural relation(s)", total_count))
    end
end

return M
