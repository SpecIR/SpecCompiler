---Cross-reference relation type for sections by label.
---Targets: SECTION objects via # selector.
---
---@module xref_secp

local M = {}

M.relation = {
    id = "XREF_SECP",
    extends = "LABEL_REF",
    long_name = "Section Reference (Label)",
    description = "Cross-reference to a section by its scoped label",
    target_type_ref = "SECTION",
}

M.handler = {
    name = "xref_secp_handler",
    -- Same display rule as XREF_SEC: "<hierarchical-number> <title>".
    -- Label-resolved section refs reach the same SECTION objects, so the
    -- formatting should be identical regardless of which selector the author
    -- used to point at them.
    on_render_Link = function(target, _ctx)
        local title = target.title or ""
        local number = target.pid and target.pid:match("sec([%d%.]+)$")
        if number and title ~= "" then return number .. " " .. title end
        if title ~= "" then return title end
        return target.pid
    end,
}

return M
