local view_utils = require("pipeline.shared.view_utils")
local make_link_target = view_utils.make_link_target
---Test Results Matrix View for sw_docs.
---Generates a Pandoc Table showing VC -> TR traceability with pass/fail status.
---
---Usage in markdown:
---  `test_results_matrix:`
---
---Returns a Pandoc Table element that works with both DOCX and HTML5 outputs.
---
---@module test_results_matrix

local schema = {
    id = "TEST_RESULTS_MATRIX",
    extends = "TABLE_VIEW",
    long_name = "Test Results Matrix",
    description = "VC to TR traceability with pass/fail results",
    inline_prefix = "test_results_matrix"
}


---Generate test results matrix as a Pandoc Table.
---Queries spec_relations directly for TR -> VC traceability with result status.
---@param data DataManager
---@param spec_id string Specification identifier
---@param options table|nil View options
---@return pandoc.Block Pandoc Table element
local function build_block(dctx)
    local data = dctx.data
    local spec_id = dctx.spec_id or "default"
    -- Query spec_relations for TR -> VC traceability
    -- Also join with spec_attribute_values to get the result status
    -- Scoped to VCs in the current specification
    local relations = data:query_all([[
        SELECT DISTINCT
            vc.pid AS vc_pid,
            vc.title_text AS vc_title,
            vc.specification_ref AS vc_spec,
            tr.pid AS tr_pid,
            tr.title_text AS tr_title,
            tr.specification_ref AS tr_spec,
            COALESCE(ev.key, av.string_value) AS result
        FROM spec_relations r
        JOIN spec_objects tr ON r.source_object_id = tr.id
        JOIN spec_objects vc ON r.target_object_id = vc.id
        LEFT JOIN spec_attribute_values av ON av.owner_object_id = tr.id
            AND av.name = 'result'
        LEFT JOIN enum_values ev ON av.enum_ref = ev.identifier
        WHERE tr.type_ref = 'TR'
          AND vc.type_ref = 'VC'
          AND vc.specification_ref = :spec_id
        ORDER BY vc.pid, tr.pid
    ]], { spec_id = spec_id })

    if not relations or #relations == 0 then
        return pandoc.Para({pandoc.Str("No VC-TR test result relations found.")})
    end

    -- Build Pandoc Table
    -- Header row
    local header_row = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC Title")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("TR ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Result")})})}
    }

    -- Body rows
    local body_rows = {}
    for _, rel in ipairs(relations) do
        -- Style the result based on pass/fail
        local result_str = rel.result or "Not Run"
        local result_inline
        if result_str == "Pass" then
            result_inline = pandoc.Strong({pandoc.Str("PASS")})
        elseif result_str == "Fail" then
            result_inline = pandoc.Emph({pandoc.Str("FAIL")})
        else
            result_inline = pandoc.Str(result_str)
        end

        local vc_pid = rel.vc_pid or ""
        local vc_href = make_link_target(vc_pid, rel.vc_spec or spec_id, spec_id)
        local tr_pid = rel.tr_pid or ""
        local tr_href = make_link_target(tr_pid, rel.tr_spec or spec_id, spec_id)

        table.insert(body_rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(vc_pid)}, vc_href)})},
            {pandoc.Plain({pandoc.Str(rel.vc_title or "")})},
            {pandoc.Plain({pandoc.Link({pandoc.Str(tr_pid)}, tr_href)})},
            {pandoc.Plain({result_inline})}
        })
    end

    -- Column alignments
    local aligns = {
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignCenter
    }

    -- Column widths (0 = auto)
    local widths = {0, 0, 0, 0}

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

return {
    kind = "view",
    schema = schema,
    hooks = {
        build_block = build_block,
    }
}
