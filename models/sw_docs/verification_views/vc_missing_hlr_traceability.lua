local SQL = require("models.sw_docs.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_traceability_vc_missing_hlr",
    policy_key = "traceability_vc_to_hlr",
    sql = SQL.view_traceability_vc_missing_hlr,
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Verification case '%s' has no traceability link to an HLR",
            label
        )
    end
}

return M
