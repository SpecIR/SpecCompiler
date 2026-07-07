local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "bounds_violation",
        view = "view_object_bounds_violation",
        policy_key = "bounds_violation",
        sql = SQL.view_object_bounds_violation,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Value %s for attribute '%s' outside bounds [%s, %s]",
                row.actual_value, row.attribute_name,
                row.min_value or "-inf", row.max_value or "inf")
        end,
    },
}
