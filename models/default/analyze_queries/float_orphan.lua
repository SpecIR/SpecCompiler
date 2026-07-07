local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "float_orphan",
        view = "view_float_orphan",
        policy_key = "float_orphan",
        sql = SQL.view_float_orphan,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Float '%s' has no parent object", row.label or row.float_id)
        end,
    },
}
