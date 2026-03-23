local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_object_missing_required",
    policy_key = "missing_required",
    sql = SQL.view_object_missing_required,
    message = function(row)
        return string.format("Object missing required attribute '%s' on %s",
            row.missing_attribute, row.object_title or row.object_id)
    end
}

return M
