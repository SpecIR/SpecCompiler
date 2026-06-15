local SQL = require("models.sw_docs.verification_views.sql")

return {
    kind = "verification",
    schema = {
        id = "traceability_hlr_to_vc",
        view = "view_traceability_hlr_missing_vc",
        policy_key = "traceability_hlr_to_vc",
        sql = SQL.view_traceability_hlr_missing_vc,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "High-level requirement '%s' is not covered by any VC",
                label
            )
        end
    },
}
