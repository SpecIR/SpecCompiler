local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
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
