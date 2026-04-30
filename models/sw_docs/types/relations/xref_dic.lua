---Cross-reference relation type for dictionary entries.
---Targets: DIC object type.
---
---@module xref_dic

local M = {}

M.relation = {
    id = "XREF_DIC",
    extends = "PID_REF",
    long_name = "Dictionary Reference",
    description = "Cross-reference to a dictionary entry",
    target_type_ref = "DIC",
}

M.handler = {
    name = "xref_dic_handler",
    -- Render dictionary refs as the entry's title alone (the prose context
    -- already implies "this is a term"; the PID would be noise).
    on_render_Link = function(target, _ctx)
        if target.title and target.title ~= "" then
            return target.title
        end
    end,
}

return M
