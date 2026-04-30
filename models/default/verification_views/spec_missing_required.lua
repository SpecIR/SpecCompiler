local SQL = require("models.default.verification_views.sql")

local M = {}

M.verification_view = {
    view = "view_spec_missing_required",
    policy_key = "spec_missing_required",
    sql = SQL.view_spec_missing_required,
    message = function(row)
        return string.format("Specification missing required attribute '%s'",
            row.missing_attribute)
    end
}

return M
