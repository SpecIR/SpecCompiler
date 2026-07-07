local SQL = require("models.sw_docs.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "traceability_vc_to_hlr",
        view = "view_traceability_vc_missing_hlr",
        policy_key = "traceability_vc_to_hlr",
        sql = SQL.view_traceability_vc_missing_hlr,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "Verification case '%s' has no traceability link to an HLR",
                label
            )
        end,
    },
}
