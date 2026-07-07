local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "float_duplicate_label",
        view = "view_float_duplicate_label",
        policy_key = "float_duplicate_label",
        sql = SQL.view_float_duplicate_label,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Duplicate float label '%s' in specification (found %d)", row.label, row.duplicate_count)
        end,
    },
}
