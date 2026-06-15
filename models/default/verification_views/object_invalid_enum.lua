local SQL = require("models.default.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "invalid_enum",
        view = "view_object_invalid_enum",
        policy_key = "invalid_enum",
        sql = SQL.view_object_invalid_enum,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local msg = string.format("Invalid enum value for attribute '%s' (value: '%s')",
                row.attribute_name, row.raw_value or "nil")
            if row.valid_values and row.valid_values ~= "" then
                msg = msg .. "; valid values: " .. row.valid_values
            end
            return msg
        end,
    },
}
