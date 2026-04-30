---Base relation type for PID-based references (@ selector).
---Owns resolution logic for @ links. Concrete types use extends = "PID_REF".
---
---@module pid_ref
local Queries = require("db.queries")
local M = {}

M.relation = {
    id = "PID_REF",
    long_name = "PID Reference",
    description = "Base relation type for PID-based references (@ selector)",
    link_selector = "@",
}

---Default display rule for PID-based refs. Mirrors LABEL_REF's convention:
---sections by title, other objects by PID, floats by "<caption> <number>".
---Concrete subtypes (XREF_SEC, XREF_DECOMPOSITION, ...) can override by
---defining their own on_render_Link.
M.handler = {
    name = "pid_ref_handler",
    on_render_Link = function(target, _ctx)
        if target.kind == "float" then
            local caption = target.caption or "Item"
            return caption .. " " .. (target.number or "?")
        end
        if target.type_ref == "SECTION" and target.title and target.title ~= "" then
            return target.title
        end
        return target.pid
    end,
}

---Resolve a PID reference. Same-spec first, then cross-doc fallback.
---@param data DataManager
---@param spec_id string Specification ID
---@param target_text string Raw link target text (may have leading @)
---@param _source_object_id integer|nil Source object ID (unused for PID resolution)
---@return table|nil target {id, type_ref, kind='object'}
---@return boolean is_ambiguous Always false for PID (unique by definition)
function M.resolve(data, spec_id, target_text, _source_object_id)
    local pid = target_text:match("^@?(.+)$")
    if not pid or pid == "" then return nil, false end

    local result = data:query_one(Queries.resolution.object_by_pid_in_spec,
        { spec = spec_id, pid = pid })

    if not result then
        result = data:query_one(Queries.resolution.object_by_pid_cross_doc,
            { pid = pid })
    end

    if result then
        result.kind = "object"
    end
    return result, false
end

return M
