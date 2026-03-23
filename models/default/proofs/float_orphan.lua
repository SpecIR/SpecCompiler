local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_float_orphan",
    policy_key = "float_orphan",
    sql = SQL.view_float_orphan,
    message = function(row)
        return string.format("Float '%s' has no parent object", row.label or row.float_id)
    end
}

return M
