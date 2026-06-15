local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "view_materialization_failure",
        view = "view_view_materialization_failure",
        policy_key = "view_materialization_failure",
        sql = SQL.view_view_materialization_failure,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("View '%s' materialization failed",
                row.view_type_ref or row.view_id)
        end,
    },
}
