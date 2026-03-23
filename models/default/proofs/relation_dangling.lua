local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_relation_dangling",
    policy_key = "dangling_relation",
    sql = SQL.view_relation_dangling,
    message = function(row)
        return string.format("Dangling relation: target '%s' points to non-existent object", row.target_object_id or row.target_float_id)
    end
}

return M
