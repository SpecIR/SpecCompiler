---Allocation Matrix View for sw_docs.
---Generates a Pandoc Table showing HLR -> SF -> FD -> CSC -> CSU allocation chain.
---Computes transitive traceability through the layered design indirection.
---
---Usage in markdown:
---  Inline syntax (alone in its own paragraph):
---    `allocation_matrix:`                    -- full matrix
---    `allocation_matrix: status=complete`    -- only complete chains
---    `allocation_matrix: status=incomplete`  -- only broken chains (gap analysis)
---
---Renders live from the database at EMIT (like every other view), so cached
---documents always reflect the current cross-document allocation data.
---
---@module allocation_matrix

local schema = {
    id = "ALLOCATION_MATRIX",
    long_name = "Allocation Matrix",
    description = "HLR to CSU allocation chain via SF, FD, CSC",
    inline_prefix = "allocation_matrix"
}

local view_utils = require("pipeline.shared.view_utils")
local make_link_target = view_utils.make_link_target

---Generate allocation matrix as a Pandoc Table.
---Queries the full HLR -> SF -> FD -> CSC -> CSU chain via spec_relations.
---@param data DataManager
---@param spec_id string Specification identifier
---@param options table|nil View options
---@return pandoc.Block Pandoc Table element
local function generate(params, data, spec_id)
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

    -- status= param filters by chain completeness (complete | incomplete)
    local status_filter = params and params.status
    if status_filter == "complete" or status_filter == "incomplete" then
        local wanted_complete = status_filter == "complete"
        local filtered = {}
        for _, rel in ipairs(relations or {}) do
            if (rel.chain_status == "Complete") == wanted_complete then
                table.insert(filtered, rel)
            end
        end
        relations = filtered
    end

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

return {
    kind = "view",
    schema = schema,
    hooks = {
        ---EMIT: Render a standalone `allocation_matrix:` paragraph
        ---(block-promoted by emit_view, which already matched the prefix).
        ---@param ctx Context
        ---@return table|nil Replacement block
        render_block = function(ctx)
            if ctx.subject.content == nil then return nil end

            local data = ctx.data
            local spec_id = ctx.spec_id or "default"

            if not data or not pandoc then
                return nil
            end

            return generate(ctx.subject.params or {}, data, spec_id)
        end,
    }
}
