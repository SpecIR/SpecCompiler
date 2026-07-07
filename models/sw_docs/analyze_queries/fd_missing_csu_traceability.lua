local SQL = require("models.sw_docs.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "traceability_fd_to_csu",
        view = "view_traceability_fd_missing_csu",
        policy_key = "traceability_fd_to_csu",
        sql = SQL.view_traceability_fd_missing_csu,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "Functional description '%s' has no traceability link to a CSU",
                label
            )
        end,
    },
}
