local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_float_render_failure",
    policy_key = "float_render_failure",
    sql = SQL.view_float_render_failure,
    message = function(row)
        return string.format("Float '%s' external render failed", row.label or row.float_id)
    end
}

return M
