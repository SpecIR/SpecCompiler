local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_relation_ambiguous",
    policy_key = "ambiguous_relation",
    sql = SQL.view_relation_ambiguous,
    message = function(row)
        return string.format("Ambiguous relation '%s' — multiple targets or inference rules matched", row.target_text)
    end
}

return M
