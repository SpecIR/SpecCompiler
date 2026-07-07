local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "invalid_date",
        view = "view_object_invalid_date",
        policy_key = "invalid_date",
        sql = SQL.view_object_invalid_date,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Invalid date format for attribute '%s' (expected YYYY-MM-DD, got: '%s')",
                row.attribute_name, row.date_value or "nil")
        end,
    },
}
