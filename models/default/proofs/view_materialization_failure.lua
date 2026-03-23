local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_view_materialization_failure",
    policy_key = "view_materialization_failure",
    sql = SQL.view_view_materialization_failure,
    message = function(row)
        return string.format("View '%s' materialization failed",
            row.view_type_ref or row.view_id)
    end,
}

return M
