local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_relation_unresolved",
    policy_key = "unresolved_relation",
    sql = SQL.view_relation_unresolved,
    message = function(row)
        return string.format("Unresolved link: '%s' (no matching object found)", row.target_text)
    end
}

return M
