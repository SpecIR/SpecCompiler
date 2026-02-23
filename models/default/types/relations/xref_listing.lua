---Cross-reference relation type for listings.
---Targets: LISTING float type.
---
---@module xref_listing

local M = {}

M.relation = {
    id = "XREF_LISTING",
    extends = "LABEL_REF",
    long_name = "Listing Reference",
    description = "Cross-reference to a code listing",
    target_type_ref = "LISTING",
}

return M
