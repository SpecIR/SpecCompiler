local view_utils = require("pipeline.shared.view_utils")
local make_link_target = view_utils.make_link_target
---Traceability Matrix View for sw_docs.
---Generates a Pandoc Table showing HLR -> VC traceability with TR results.
---
---Usage in markdown:
---  Inline syntax: `traceability_matrix:` (alone in its own paragraph)
---
---@module traceability_matrix

local schema = {
    id = "TRACEABILITY_MATRIX",
    extends = "TABLE_VIEW",
    long_name = "Traceability Matrix",
    description = "HLR to VC to TR traceability with test results",
    inline_prefix = "traceability_matrix"
}


---Format a TR result value into Pandoc inlines with a status indicator.
---@param result string|nil
---@return table[] inlines
local function format_result(result)
    if result == "Pass" then
        return {pandoc.Strong({pandoc.Str("✓ Pass")})}
    elseif result == "Fail" then
        return {pandoc.Strong({pandoc.Str("✗ Fail")})}
    elseif result == "Blocked" then
        return {pandoc.Str("⊘ Blocked")}
    else
        return {pandoc.Str("— Not Run")}
    end
end

---Generate traceability matrix as a Pandoc Table.
---@param data DataManager
---@param spec_id string
---@param options table|nil
---@return pandoc.Block
local function build_block(dctx)
    local data = dctx.data
    local spec_id = dctx.spec_id or "default"
    local rows_data = data:query_all([[
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

    if not rows_data or #rows_data == 0 then
        return pandoc.Para({pandoc.Str("No HLR-VC traceability relations found.")})
    end

    local header = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Result")})})}
    }

    local body_rows = {}
    for _, row in ipairs(rows_data) do
        local hlr_pid = row.hlr_pid or ""
        local vc_pid = row.vc_pid or ""
        local hlr_href = make_link_target(hlr_pid, row.hlr_spec or spec_id, spec_id)
        local vc_href = make_link_target(vc_pid, row.vc_spec or spec_id, spec_id)

        table.insert(body_rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(hlr_pid)}, hlr_href)})},
            {pandoc.Plain({pandoc.Str(row.hlr_title or "")})},
            {pandoc.Plain({pandoc.Link({pandoc.Str(vc_pid)}, vc_href)})},
            {pandoc.Plain({pandoc.Str(row.vc_title or "")})},
            {pandoc.Plain(format_result(row.result))}
        })
    end

    local aligns = {
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignCenter
    }
    local widths = {0, 0, 0, 0, 0}

    local tbl = pandoc.SimpleTable({}, aligns, widths, header, body_rows)
    return pandoc.utils.from_simple_table(tbl)
end

return {
    kind = "view",
    schema = schema,
    hooks = {
        -- Expose the data generator as the view's `generate` hook (matching the
        -- sibling matrix views), so the host indexes it for data-view lookups.
        build_block = build_block,
    }
}
