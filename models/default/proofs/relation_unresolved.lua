local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_relation_unresolved",
    policy_key = "unresolved_relation",
    sql = SQL.view_relation_unresolved,
    message = function(row)
        return string.format("Unresolved link: '%s' (no matching object found)", row.target_text)
    end
}

return M
