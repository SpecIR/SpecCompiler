local SQL = require("models.sw_docs.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "traceability_csu_to_fd",
        view = "view_traceability_csu_missing_fd",
        policy_key = "traceability_csu_to_fd",
        sql = SQL.view_traceability_csu_missing_fd,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "CSU '%s' has no functional description (FD) allocated to it",
                label
            )
        end,
    },
}
