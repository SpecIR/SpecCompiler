local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_spec_invalid_type",
    policy_key = "spec_invalid_type",
    sql = SQL.view_spec_invalid_type,
    message = function(row)
        return string.format("Invalid specification type '%s'",
            row.type_ref or "nil")
    end
}

return M
