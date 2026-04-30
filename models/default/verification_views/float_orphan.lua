local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_float_orphan",
    policy_key = "float_orphan",
    sql = SQL.view_float_orphan,
    message = function(row)
        return string.format("Float '%s' has no parent object", row.label or row.float_id)
    end
}

return M
