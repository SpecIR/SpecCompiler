local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "cardinality_over",
        view = "view_object_cardinality_over",
        policy_key = "cardinality_over",
        sql = SQL.view_object_cardinality_over,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Object attribute '%s' has %d values, max allowed is %d",
                row.attribute_name, row.actual_count, row.max_occurs)
        end,
    },
}
