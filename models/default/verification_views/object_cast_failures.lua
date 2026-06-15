local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "invalid_cast",
        view = "view_object_cast_failures",
        policy_key = "invalid_cast",
        sql = SQL.view_object_cast_failures,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local msg = string.format("Failed to cast attribute '%s' to %s (value: '%s')",
                row.attribute_name, row.datatype, row.raw_value or "nil")
            if row.valid_values and row.valid_values ~= "" then
                msg = msg .. "; valid values: " .. row.valid_values
            end
            return msg
        end,
    },
}
