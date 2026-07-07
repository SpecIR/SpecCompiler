local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
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
