local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_float_invalid_type",
    policy_key = "float_invalid_type",
    sql = SQL.view_float_invalid_type,
    message = function(row)
        return string.format("Float '%s' has invalid type '%s'", row.label or row.float_id, row.type_ref or "nil")
    end
}

return M
