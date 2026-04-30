local SQL = require("models.sw_docs.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_traceability_tr_missing_vc",
    policy_key = "traceability_tr_to_vc",
    sql = SQL.view_traceability_tr_missing_vc,
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Test result '%s' has no traceability link to a VC",
            label
        )
    end
}

return M
