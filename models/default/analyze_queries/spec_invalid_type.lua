local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "spec_invalid_type",
        view = "view_spec_invalid_type",
        policy_key = "spec_invalid_type",
        sql = SQL.view_spec_invalid_type,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Invalid specification type '%s'",
                row.type_ref or "nil")
        end
    },
}
