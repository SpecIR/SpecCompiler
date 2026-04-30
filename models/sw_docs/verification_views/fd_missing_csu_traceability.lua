local SQL = require("models.sw_docs.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_traceability_fd_missing_csu",
    policy_key = "traceability_fd_to_csu",
    sql = SQL.view_traceability_fd_missing_csu,
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Functional description '%s' has no traceability link to a CSU",
            label
        )
    end
}

return M
