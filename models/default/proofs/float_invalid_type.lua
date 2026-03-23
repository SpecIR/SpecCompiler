local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_float_invalid_type",
    policy_key = "float_invalid_type",
    sql = SQL.view_float_invalid_type,
    message = function(row)
        return string.format("Float '%s' has invalid type '%s'", row.label or row.float_id, row.type_ref or "nil")
    end
}

return M
