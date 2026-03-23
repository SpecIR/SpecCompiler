local SQL = require("models.sw_docs.proofs.sql")

local M = {}

M.proof = {
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
