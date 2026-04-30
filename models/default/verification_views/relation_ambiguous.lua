local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_relation_ambiguous",
    policy_key = "ambiguous_relation",
    sql = SQL.view_relation_ambiguous,
    message = function(row)
        return string.format("Ambiguous relation '%s' — multiple targets or inference rules matched", row.target_text)
    end
}

return M
