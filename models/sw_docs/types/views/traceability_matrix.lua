---Traceability Matrix View for sw_docs.
---Generates a Pandoc Table showing HLR -> VC -> TR traceability with test results.
---
---Usage in markdown:
---  Inline syntax: `traceability_matrix:`
---  Code block syntax:
---    ```traceability_matrix
---    ```
---
---Both syntaxes produce a Pandoc Table via resolved_ast during TRANSFORM phase.
---
---@module traceability_matrix
local M = {}

M.view = {
    id = "TRACEABILITY_MATRIX",
    long_name = "Traceability Matrix",
    description = "HLR to VC to TR traceability with test results",
    inline_prefix = "traceability_matrix"
}

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_codeblock = prefix_matcher.codeblock_from_decl(M.view)

---Build link target, using cross-document .ext placeholder for objects in other specs.
---@param pid string Target PID
---@param target_spec string Specification owning the target object
---@param current_spec string Current specification being rendered
---@return string Link href
local function make_link_target(pid, target_spec, current_spec)
    if target_spec == current_spec then
        return "#" .. pid
    else
        return target_spec .. ".ext#" .. pid
    end
end

---Generate traceability matrix as a Pandoc Table.
---Queries spec_relations for VC -> HLR and TR -> VC traceability.
---@param data DataManager
---@param spec_id string Specification identifier
---@param options table|nil View options
---@return pandoc.Block Pandoc Table element
function M.generate(data, spec_id, options)
    -- Query HLR -> VC -> TR chain with test results
    -- TR traces to VC (via traceability attribute -> spec_relations)
    -- VC traces to HLR (via traceability attribute -> spec_relations)
    -- Scoped to VCs in the current specification
    local relations = data:query_all([[
        SELECT DISTINCT
            hlr.pid AS hlr_pid,
            hlr.title_text AS hlr_title,
            hlr.specification_ref AS hlr_spec,
            vc.pid AS vc_pid,
            vc.title_text AS vc_title,
            vc.specification_ref AS vc_spec,
            tr.pid AS tr_pid,
            COALESCE(ev.key, av.string_value) AS result
        FROM spec_relations vc_hlr
        JOIN spec_objects vc ON vc_hlr.source_object_id = vc.id
        JOIN spec_objects hlr ON vc_hlr.target_object_id = hlr.id
        LEFT JOIN spec_relations tr_vc ON tr_vc.target_object_id = vc.id
        LEFT JOIN spec_objects tr ON tr_vc.source_object_id = tr.id AND tr.type_ref = 'TR'
        LEFT JOIN spec_attribute_values av ON tr.id = av.owner_object_id AND av.name = 'result'
        LEFT JOIN enum_values ev ON av.enum_ref = ev.identifier
        WHERE vc.type_ref = 'VC'
          AND hlr.type_ref = 'HLR'
          AND vc.specification_ref = :spec_id
        ORDER BY hlr.pid, vc.pid, tr.pid
    ]], { spec_id = spec_id })

    if not relations or #relations == 0 then
        return pandoc.Para({pandoc.Str("No HLR-VC traceability relations found.")})
    end

    -- Build Pandoc Table
    -- Header row with Result column
    local header_row = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Result")})})}
    }

    -- Body rows with result status
    local body_rows = {}
    for _, rel in ipairs(relations) do
        -- Format result with color indicator
        local result_text = rel.result or "Not Run"
        local result_inlines = {}

        if result_text == "Pass" then
            result_inlines = {pandoc.Strong({pandoc.Str("✓ Pass")})}
        elseif result_text == "Fail" then
            result_inlines = {pandoc.Strong({pandoc.Str("✗ Fail")})}
        elseif result_text == "Blocked" then
            result_inlines = {pandoc.Str("⊘ Blocked")}
        else
            result_inlines = {pandoc.Str("— Not Run")}
        end

        local hlr_pid = rel.hlr_pid or ""
        local hlr_href = make_link_target(hlr_pid, rel.hlr_spec or spec_id, spec_id)
        local vc_pid = rel.vc_pid or ""
        local vc_href = make_link_target(vc_pid, rel.vc_spec or spec_id, spec_id)

        table.insert(body_rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(hlr_pid)}, hlr_href)})},
            {pandoc.Plain({pandoc.Str(rel.hlr_title or "")})},
            {pandoc.Plain({pandoc.Link({pandoc.Str(vc_pid)}, vc_href)})},
            {pandoc.Plain({pandoc.Str(rel.vc_title or "")})},
            {pandoc.Plain(result_inlines)}
        })
    end

    -- Column alignments
    local aligns = {
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignCenter
    }

    -- Column widths (0 = auto)
    local widths = {0, 0, 0, 0, 0}

    -- Create SimpleTable and convert to full Table
    local simple_table = pandoc.SimpleTable(
        {},           -- caption (empty)
        aligns,
        widths,
        header_row,
        body_rows
    )

    return pandoc.utils.from_simple_table(simple_table)
end

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "traceability_matrix_handler",
    prerequisites = {"spec_objects", "spec_relations"},

    ---TRANSFORM: Pre-compute traceability matrix and store in resolved_ast.
    ---@param data DataManager
    ---@param contexts Context[]
    ---@param diagnostics Diagnostics
    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local spec_id = ctx.spec_id or "default"

            -- Find all traceability_matrix views for this spec
            local views = data:query_all([[
                SELECT id FROM spec_views
                WHERE specification_ref = :spec_id
                  AND view_type_ref = 'TRACEABILITY_MATRIX'
                  AND resolved_ast IS NULL
            ]], { spec_id = spec_id })

            for _, view in ipairs(views or {}) do
                -- Generate the table
                local table_elem = M.generate(data, spec_id, {})

                -- Serialize to JSON and store in resolved_ast
                if table_elem and pandoc then
                    local doc = pandoc.Pandoc({table_elem})
                    local ast_json = pandoc.write(doc, "json")

                    data:execute([[
                        UPDATE spec_views SET resolved_ast = :ast
                        WHERE id = :id
                    ]], { id = view.id, ast = ast_json })
                end
            end
        end
    end,

    ---EMIT: Render inline Code elements with traceability_matrix: syntax.
    ---NOTE: Inline Code handlers cannot return Blocks (Pandoc constraint).
    ---Returns nil to let emit_view's Para walker handle block generation.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return nil Always returns nil (Para walker handles block output)
    on_render_Code = function(code, ctx)
        -- Return nil - let emit_view's Para walker handle this.
        -- Inline Code cannot be replaced with Block elements.
        return nil
    end,

    ---EMIT: Render CodeBlock elements with traceability_matrix class.
    ---Handles both class-based syntax (```traceability_matrix) and
    ---text-based syntax from Para handler (traceability_matrix:)
    ---@param block table Pandoc CodeBlock element
    ---@param ctx Context
    ---@return table|nil Replacement block
    on_render_CodeBlock = function(block, ctx)
        if not match_codeblock(block) then return nil end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"

        if not data or not pandoc then
            return nil
        end

        -- Look up resolved_ast from spec_views
        local view = data:query_one([[
            SELECT resolved_ast FROM spec_views
            WHERE specification_ref = :spec_id
              AND view_type_ref = 'TRACEABILITY_MATRIX'
              AND resolved_ast IS NOT NULL
            LIMIT 1
        ]], { spec_id = spec_id })

        if view and view.resolved_ast then
            local ok, doc = pcall(pandoc.read, view.resolved_ast, "json")
            if ok and doc and doc.blocks and #doc.blocks > 0 then
                return doc.blocks[1]
            end
        end

        -- Fallback: generate on-the-fly
        return M.generate(data, spec_id, {})
    end
}

return M
