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

return M
