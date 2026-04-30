---Cross-reference relation type for software decomposition entries.
---Targets: CSC and CSU object types (MIL-STD-498 decomposition).
---
---@module xref_decomposition

local M = {}

M.relation = {
    id = "XREF_DECOMPOSITION",
    extends = "PID_REF",
    long_name = "Decomposition Reference",
    description = "Cross-reference to a software decomposition element (CSC or CSU)",
    target_type_ref = "CSC,CSU",
}

M.handler = {
    name = "xref_decomposition_handler",
    -- Render decomposition refs as "<TYPE> <title>" (e.g. "CSC Authentication")
    -- so the code identifier stays visible next to the human-readable title.
    on_render_Link = function(target, _ctx)
        if target.title and target.title ~= "" then
            return target.type_ref .. " " .. target.title
        end
    end,
}

return M
