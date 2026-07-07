local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "float_render_failure",
        view = "view_float_render_failure",
        policy_key = "float_render_failure",
        sql = SQL.view_float_render_failure,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Float '%s' external render failed", row.label or row.float_id)
        end,
    },
}
