local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "unresolved_relation",
        view = "view_relation_unresolved",
        policy_key = "unresolved_relation",
        sql = SQL.view_relation_unresolved,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Unresolved link: '%s' (no matching object found)", row.target_text)
        end,
    },
}
