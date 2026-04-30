local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_float_render_failure",
    policy_key = "float_render_failure",
    sql = SQL.view_float_render_failure,
    message = function(row)
        return string.format("Float '%s' external render failed", row.label or row.float_id)
    end
}

return M
