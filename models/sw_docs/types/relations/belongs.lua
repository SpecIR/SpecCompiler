---BELONGS relation module for SpecCompiler.
---Represents HLR membership in a Software Function.

local M = {}

M.relation = {
    id = "BELONGS",
    long_name = "Belongs To",
    description = "Requirement belongs to a functional grouping (inferred from document hierarchy)",
    is_structural = 1,
    source_type_ref = "HLR",
    target_type_ref = "SF",
}

return M
