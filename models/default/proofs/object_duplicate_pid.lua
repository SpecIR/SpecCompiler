local SQL = require("models.default.proofs.sql")

local M = {}

M.proof = {
    view = "view_object_duplicate_pid",
    policy_key = "object_duplicate_pid",
    sql = SQL.view_object_duplicate_pid,
    message = function(row)
        return string.format("Duplicate PID '%s' on object '%s' in '%s'",
            row.pid, row.title_text or tostring(row.object_id), row.specification_ref or "unknown")
    end
}

return M
