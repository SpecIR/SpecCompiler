local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_object_bounds_violation",
    policy_key = "bounds_violation",
    sql = SQL.view_object_bounds_violation,
    message = function(row)
        return string.format("Value %s for attribute '%s' outside bounds [%s, %s]",
            row.actual_value, row.attribute_name,
            row.min_value or "-inf", row.max_value or "inf")
    end
}

return M
