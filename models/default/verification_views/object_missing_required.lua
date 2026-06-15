local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "missing_required",
        view = "view_object_missing_required",
        policy_key = "missing_required",
        sql = SQL.view_object_missing_required,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Object missing required attribute '%s' on %s",
                row.missing_attribute, row.object_title or row.object_id)
        end,
    },
}
