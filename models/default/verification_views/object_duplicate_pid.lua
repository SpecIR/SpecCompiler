local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "object_duplicate_pid",
        view = "view_object_duplicate_pid",
        policy_key = "object_duplicate_pid",
        sql = SQL.view_object_duplicate_pid,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Duplicate PID '%s' on object '%s' in '%s'",
                row.pid, row.title_text or tostring(row.object_id), row.specification_ref or "unknown")
        end,
    },
}
