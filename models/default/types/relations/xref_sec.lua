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

return M
