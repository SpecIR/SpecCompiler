local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "spec_missing_required",
        view = "view_spec_missing_required",
        policy_key = "spec_missing_required",
        sql = SQL.view_spec_missing_required,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Specification missing required attribute '%s'",
                row.missing_attribute)
        end,
    },
}
