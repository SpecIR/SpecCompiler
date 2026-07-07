local SQL = require("models.sw_docs.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "traceability_llr_to_vc",
        view = "view_traceability_llr_missing_vc",
        policy_key = "traceability_llr_to_vc",
        sql = SQL.view_traceability_llr_missing_vc,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "Low-level requirement '%s' is not covered by any VC",
                label
            )
        end,
    },
}
