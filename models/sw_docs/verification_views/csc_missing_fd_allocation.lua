local SQL = require("models.sw_docs.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "traceability_csc_to_fd",
        view = "view_traceability_csc_missing_fd",
        policy_key = "traceability_csc_to_fd",
        sql = SQL.view_traceability_csc_missing_fd,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "CSC '%s' has no functional description (FD) allocated to it",
                label
            )
        end,
    },
}
