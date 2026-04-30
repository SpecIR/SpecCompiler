local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_object_cardinality_over",
    policy_key = "cardinality_over",
    sql = SQL.view_object_cardinality_over,
    message = function(row)
        return string.format("Object attribute '%s' has %d values, max allowed is %d",
            row.attribute_name, row.actual_count, row.max_occurs)
    end
}

return M
