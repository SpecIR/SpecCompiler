local SQL = require("models.sw_docs.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "traceability_hlr_allocation",
        view = "view_traceability_hlr_missing_allocation",
        policy_key = "traceability_hlr_allocation",
        sql = SQL.view_traceability_hlr_missing_allocation,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local label = row.object_pid or row.object_title or row.object_id
            return string.format(
                "HLR '%s' has no complete allocation chain (SF -> FD -> CSC)",
                label
            )
        end,
    },
}
