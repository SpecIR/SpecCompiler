local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_object_cast_failures",
    policy_key = "invalid_cast",
    sql = SQL.view_object_cast_failures,
    message = function(row)
        local msg = string.format("Failed to cast attribute '%s' to %s (value: '%s')",
            row.attribute_name, row.datatype, row.raw_value or "nil")
        if row.valid_values and row.valid_values ~= "" then
            msg = msg .. "; valid values: " .. row.valid_values
        end
        return msg
    end
}

return M
