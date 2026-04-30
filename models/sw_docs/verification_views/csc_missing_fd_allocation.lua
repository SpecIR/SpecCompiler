local SQL = require("models.sw_docs.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_traceability_csc_missing_fd",
    policy_key = "traceability_csc_to_fd",
    sql = SQL.view_traceability_csc_missing_fd,
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "CSC '%s' has no functional description (FD) allocated to it",
            label
        )
    end
}

return M
