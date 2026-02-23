---Test Results Matrix View for sw_docs.
---Generates a Pandoc Table showing VC -> TR traceability with pass/fail status.
---
---Usage in markdown:
---  `test_results_matrix:`
---
---Returns a Pandoc Table element that works with both DOCX and HTML5 outputs.
---
---@module test_results_matrix
local M = {}

M.view = {
    id = "TEST_RESULTS_MATRIX",
    long_name = "Test Results Matrix",
    description = "VC to TR traceability with pass/fail results",
    inline_prefix = "test_results_matrix"
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

---Generate test results matrix as a Pandoc Table.
---Queries spec_relations directly for TR -> VC traceability with result status.
---@param data DataManager
---@param spec_id string Specification identifier
---@param options table|nil View options
---@return pandoc.Block Pandoc Table element
function M.generate(data, spec_id, options)
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

M.handler = {
    name = "test_results_matrix_handler",
    prerequisites = {"spec_objects", "spec_relations"},

    on_render_Code = function()
        return nil
    end,

    on_render_CodeBlock = function(block, ctx)
        if not match_codeblock(block) then return nil end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"
        if not data or not pandoc then
            return nil
        end

        return M.generate(data, spec_id, {})
    end,
}

return M
