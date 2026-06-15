local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "float_invalid_type",
        view = "view_float_invalid_type",
        policy_key = "float_invalid_type",
        sql = SQL.view_float_invalid_type,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            return string.format("Float '%s' has invalid type '%s'", row.label or row.float_id, row.type_ref or "nil")
        end,
    },
}
