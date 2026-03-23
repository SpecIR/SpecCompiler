---Allocation Matrix View for sw_docs.
---Generates a Pandoc Table showing HLR -> SF -> FD -> CSC -> CSU allocation chain.
---Computes transitive traceability through the layered design indirection.
---
---Usage in markdown:
---  Inline syntax: `allocation_matrix:`
---  Code block syntax:
---    ```allocation_matrix
---    ```
---
---Both syntaxes produce a Pandoc Table via resolved_ast during TRANSFORM phase.
---
---@module allocation_matrix
local M = {}

M.view = {
    id = "ALLOCATION_MATRIX",
    long_name = "Allocation Matrix",
    description = "HLR to CSU allocation chain via SF, FD, CSC",
    inline_prefix = "allocation_matrix"
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

---Generate allocation matrix as a Pandoc Table.
---Queries the full HLR -> SF -> FD -> CSC -> CSU chain via spec_relations.
---@param data DataManager
---@param spec_id string Specification identifier
---@param options table|nil View options
---@return pandoc.Block Pandoc Table element
function M.generate(data, spec_id, options)
    local relations = data:query_all([[
        SELECT DISTINCT
            hlr.pid AS hlr_pid,
            hlr.title_text AS hlr_title,
            hlr.specification_ref AS hlr_spec,
            sf.pid AS sf_pid,
            sf.specification_ref AS sf_spec,
            fd.pid AS fd_pid,
            fd.specification_ref AS fd_spec,
            csc.pid AS csc_pid,
            csc.specification_ref AS csc_spec,
            csu.pid AS csu_pid,
            csu.specification_ref AS csu_spec,
            CASE
                WHEN sf.id IS NULL THEN 'No SF'
                WHEN fd.id IS NULL THEN 'No FD'
                WHEN csc.id IS NULL THEN 'No CSC'
                WHEN csu.id IS NULL THEN 'No CSU'
                ELSE 'Complete'
            END AS chain_status
        FROM spec_objects hlr
        LEFT JOIN spec_relations r1 ON r1.source_object_id = hlr.id
            AND r1.type_ref = 'BELONGS'
        LEFT JOIN spec_objects sf ON sf.id = r1.target_object_id
            AND sf.type_ref = 'SF'
        LEFT JOIN spec_relations r2 ON r2.target_object_id = sf.id
            AND r2.type_ref = 'REALIZES'
        LEFT JOIN spec_objects fd ON fd.id = r2.source_object_id
            AND fd.type_ref = 'FD'
        LEFT JOIN spec_relations r3 ON r3.source_object_id = fd.id
        LEFT JOIN spec_objects csc ON csc.id = r3.target_object_id
            AND csc.type_ref = 'CSC'
        LEFT JOIN spec_relations r4 ON r4.target_object_id = csc.id
            AND r4.source_attribute = 'traceability'
        LEFT JOIN spec_objects csu ON csu.id = r4.source_object_id
            AND csu.type_ref = 'CSU'
        WHERE hlr.type_ref = 'HLR'
        ORDER BY hlr.pid, sf.pid, fd.pid, csc.pid, csu.pid
    ]], {})

    if not relations or #relations == 0 then
        return pandoc.Para({pandoc.Str("No HLR allocation chain data found.")})
    end

    -- Build Pandoc Table
    local header_row = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("SF")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("FD")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("CSC")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("CSU")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Status")})})}
    }

    local body_rows = {}
    for _, rel in ipairs(relations) do
        local function pid_cell(pid, rel_spec)
            if not pid or pid == "" then
                return {pandoc.Plain({pandoc.Str("—")})}
            end
            local href = make_link_target(pid, rel_spec or spec_id, spec_id)
            return {pandoc.Plain({pandoc.Link({pandoc.Str(pid)}, href)})}
        end

        -- Format status with indicator
        local status_text = rel.chain_status or "Unknown"
        local status_inlines
        if status_text == "Complete" then
            status_inlines = {pandoc.Strong({pandoc.Str("Complete")})}
        else
            status_inlines = {pandoc.Str(status_text)}
        end

        table.insert(body_rows, {
            pid_cell(rel.hlr_pid, rel.hlr_spec),
            {pandoc.Plain({pandoc.Str(rel.hlr_title or "")})},
            pid_cell(rel.sf_pid, rel.sf_spec),
            pid_cell(rel.fd_pid, rel.fd_spec),
            pid_cell(rel.csc_pid, rel.csc_spec),
            pid_cell(rel.csu_pid, rel.csu_spec),
            {pandoc.Plain(status_inlines)}
        })
    end

    local aligns = {
        pandoc.AlignLeft, pandoc.AlignLeft, pandoc.AlignLeft,
        pandoc.AlignLeft, pandoc.AlignLeft, pandoc.AlignLeft,
        pandoc.AlignCenter
    }

    local widths = {0, 0, 0, 0, 0, 0, 0}

    local simple_table = pandoc.SimpleTable(
        {},
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
    name = "allocation_matrix_handler",
    prerequisites = {"spec_objects", "spec_relations"},

    ---TRANSFORM: Pre-compute allocation matrix and store in resolved_ast.
    ---@param data DataManager
    ---@param contexts Context[]
    ---@param diagnostics Diagnostics
    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local spec_id = ctx.spec_id or "default"

            local views = data:query_all([[
                SELECT id FROM spec_views
                WHERE specification_ref = :spec_id
                  AND view_type_ref = 'ALLOCATION_MATRIX'
                  AND resolved_ast IS NULL
            ]], { spec_id = spec_id })

            for _, view in ipairs(views or {}) do
                local table_elem = M.generate(data, spec_id, {})

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

    ---EMIT: Inline Code handler returns nil (Para walker handles block output).
    on_render_Code = function(code, ctx)
        return nil
    end,

    ---EMIT: Render CodeBlock elements with allocation_matrix class.
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
              AND view_type_ref = 'ALLOCATION_MATRIX'
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
