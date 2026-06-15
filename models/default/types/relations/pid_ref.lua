---Base relation type for PID-based references (@ selector).
---Owns resolution logic for @ links. Concrete types use extends = "PID_REF".
---
---@module pid_ref
local Queries = require("db.queries")

---Resolve a PID reference. Same-spec first, then cross-doc fallback.
---@param dctx table frozen DATA ctx (dctx.data, dctx.spec_id, dctx.subject.target_text)
---@return table resolution { target = {id,type_ref,kind='object'} | nil, ambiguous = false }
local function resolve(dctx)
    local data = dctx.data
    local spec_id = dctx.spec_id
    local target_text = dctx.subject.target_text

    local pid = target_text:match("^@?(.+)$")
    if not pid or pid == "" then return { target = nil, ambiguous = false } end

    local result = data:query_one(Queries.resolution.object_by_pid_in_spec,
        { spec = spec_id, pid = pid })

    if not result then
        result = data:query_one(Queries.resolution.object_by_pid_cross_doc,
            { pid = pid })
    end

    if result then
        result.kind = "object"
    end
    return { target = result, ambiguous = false }
end

return {
    kind = "relation",
    schema = {
        id = "PID_REF",
        long_name = "PID Reference",
        description = "Base relation type for PID-based references (@ selector)",
        link_selector = "@",
    },
    hooks = {
        ---Default display rule for PID-based refs. Mirrors LABEL_REF's convention:
        ---sections by title, other objects by PID, floats by "<caption> <number>".
        ---Concrete subtypes (XREF_SEC, XREF_DECOMPOSITION, ...) can override by
        ---defining their own on_render_Link.
        render_link = function(ctx)
            local target = ctx.subject.target
            if target.kind == "float" then
                local caption = target.caption or "Item"
                return caption .. " " .. (target.number or "?")
            end
            if target.type_ref == "SECTION" and target.title and target.title ~= "" then
                return target.title
            end
            return target.pid
        end,
        resolve = resolve,
    },
}
