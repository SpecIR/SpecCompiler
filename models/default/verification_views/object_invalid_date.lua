local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_object_invalid_date",
    policy_key = "invalid_date",
    sql = SQL.view_object_invalid_date,
    message = function(row)
        return string.format("Invalid date format for attribute '%s' (expected YYYY-MM-DD, got: '%s')",
            row.attribute_name, row.date_value or "nil")
    end
}

return M
