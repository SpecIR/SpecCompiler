local SQL = require("models.sw_docs.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_traceability_hlr_missing_allocation",
    policy_key = "traceability_hlr_allocation",
    sql = SQL.view_traceability_hlr_missing_allocation,
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "HLR '%s' has no complete allocation chain (SF -> FD -> CSC)",
            label
        )
    end
}

return M
