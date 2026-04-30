---Cross-reference relation type for sections by PID.
---Targets: SECTION objects via @ selector.
---
---@module xref_sec

local M = {}

M.relation = {
    id = "XREF_SEC",
    extends = "PID_REF",
    long_name = "Section Reference (PID)",
    description = "Cross-reference to a section by its PID",
    target_type_ref = "SECTION",
}

M.handler = {
    name = "xref_sec_handler",
    -- Render section refs as "<hierarchical-number> <title>" so the link
    -- carries both the section name and its position. The hierarchical number
    -- is encoded in the PID after the "sec" marker ("TRABALHO_ACADEMICO-sec3.4"
    -- -> "3.4"); falls back to the title alone when no number is present.
    on_render_Link = function(target, _ctx)
        local title = target.title or ""
        local number = target.pid and target.pid:match("sec([%d%.]+)$")
        if number and title ~= "" then return number .. " " .. title end
        if title ~= "" then return title end
        return target.pid
    end,
}

return M
