---TABLE_VIEW base view type.
---A block view that renders a generated Pandoc table from the concrete view's
---`build_block(dctx)` DATA hook. Concrete matrix views (coverage_summary,
---csc_decomposition, requirements_summary, test_execution_matrix,
---test_results_matrix, traceability_matrix) extend this and declare ONLY their
---`build_block`; the shared `render_block` below is inherited via the host's
---extends-chain dispatch and routes standalone `` `view:` `` paragraphs
---(block-promoted by emit_view) to it.
---(allocation_matrix does not extend this -- it has a precompute phase handler
---and a resolved-AST-first render, so it keeps a custom render_block.)
---
---@module table_view
local hook_ctx = require("pipeline.shared.hook_ctx")

return {
    kind = "view",
    schema = {
        id = "TABLE_VIEW",
        long_name = "Generated Table View",
        description = "Base type for block views that render a generated table",
    },
    hooks = {
        -- EMIT (block): emit_view matched the view prefix; dispatch to the concrete
        -- view's build_block DATA hook (keyed by the matched view id) via the host
        -- carried on the ctx, building it the small data ctx it expects.
        render_block = function(ctx)
            if not ctx.data or not ctx.pandoc then return nil end
            -- Inherited lookup: host:finalize() validates build_block through the
            -- extends chain, so dispatch must look it up the same way.
            local build_block = ctx.host
                and ctx.host:get_hook_inherited("view", ctx.subject.view_id, "build_block")
            if not build_block then return nil end
            local dctx = hook_ctx.build_data(
                { log = ctx.log, model = ctx.model, config = ctx.config },
                ctx.data, ctx.diagnostics, { params = ctx.subject.params or {} },
                "build_block", ctx.spec_id)
            return build_block(dctx)
        end,
    },
}
