local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_float_duplicate_label",
    policy_key = "float_duplicate_label",
    sql = SQL.view_float_duplicate_label,
    message = function(row)
        return string.format("Duplicate float label '%s' in specification (found %d)", row.label, row.duplicate_count)
    end
}

return M
