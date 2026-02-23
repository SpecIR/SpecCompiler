---Base relation type for label-based cross-references (# selector).
---Owns scoped label resolution (local -> spec -> global). Concrete types use extends = "LABEL_REF".
---
---@module xref
local Queries = require("db.queries")
local M = {}

M.relation = {
    id = "LABEL_REF",
    long_name = "Label Reference",
    description = "Base relation type for label-based cross-references (# selector)",
    link_selector = "#",
}

---Parse target_text for explicit scope (ScopedRef: scope:prefix:label).
---@param target_text string The stored target text
---@return string|nil label The label to match against
---@return string|nil scope The explicit scope PID, or nil
local function parse_scoped_target(target_text)
    if not target_text then return nil, nil end
    local scope, prefix, label_part = target_text:match("^([^:]+):([^:]+):(.+)$")
    if scope and prefix and label_part then
        return prefix .. ":" .. label_part, scope
    end
    return target_text, nil
end

---Resolve a label reference with scoped resolution.
---Uses 3-step closest-to-global resolution with ambiguity detection.
---For explicit scope (ScopedRef), uses strict resolution with no fallback.
---@param data DataManager
---@param spec_id string Specification ID
---@param target_text string Raw link target text (may have leading #)
---@param source_object_id integer|nil Source object ID (for local scope)
---@return table|nil target {id, type_ref, kind='object'|'float'}
---@return boolean is_ambiguous True if multiple matches at same scope level
function M.resolve(data, spec_id, target_text, source_object_id)
    local raw_label = target_text:match("^#?(.+)$")
    if not raw_label or raw_label == "" then return nil, false end

    local label, explicit_scope = parse_scoped_target(raw_label)
    if not label then return nil, false end

    -- Explicit scope: strict resolution (no fallback)
    if explicit_scope then
        local scope_obj = data:query_one(Queries.resolution.scope_object_by_pid_in_spec,
            { spec_id = spec_id, pid = explicit_scope })

        if not scope_obj then
            scope_obj = data:query_one(Queries.resolution.scope_object_by_pid_cross_doc,
                { pid = explicit_scope })
        end

        if scope_obj then
            local result = data:query_one(Queries.resolution.float_by_label_in_scope_typed,
                { label = label, scope_id = scope_obj.id })
            return result, false
        end
        return nil, false
    end

    -- Implicit scoping: walk from closest scope to global

    -- Step 1: Local float scope (float's parent = source object)
    if source_object_id then
        local results = data:query_all(Queries.resolution.float_by_label_in_scope_typed,
            { label = label, scope_id = source_object_id })

        if #results == 1 then
            return results[1], false
        elseif #results > 1 then
            return results[1], true
        end
    end

    -- Step 2: Same specification (unified objects + floats)
    local results = data:query_all(Queries.resolution.unified_by_label_in_spec,
        { spec = spec_id, label = label })

    if #results == 1 then
        return results[1], false
    elseif #results > 1 then
        return results[1], true
    end

    -- Step 3: Cross-document (global fallback)
    results = data:query_all(Queries.resolution.unified_by_label_global,
        { label = label })

    if #results == 1 then
        return results[1], false
    elseif #results > 1 then
        return results[1], true
    end

    return nil, false
end

return M
