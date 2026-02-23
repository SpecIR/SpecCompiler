---BELONGS relation module for SpecCompiler.
---Represents HLR membership in a Software Function.

local M = {}

M.relation = {
    id = "BELONGS",
    extends = "PID_REF",
    long_name = "Belongs To",
    description = "Requirement belongs to a functional grouping",
    source_attribute = "belongs_to",
    source_type_ref = "HLR",
    target_type_ref = "SF",
}

return M
