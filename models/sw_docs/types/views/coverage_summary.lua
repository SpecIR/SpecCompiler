---Coverage Summary View for sw_docs.
---Generates a Pandoc Table showing VC counts and pass rates grouped by Software Function (SF).
---
---Usage in markdown:
---  Inline syntax: `coverage_summary:`
---
---@module coverage_summary

local M = {}

M.view = {
    id = "COVERAGE_SUMMARY",
    long_name = "Coverage Summary",
    description = "VC coverage grouped by Software Function",
    inline_prefix = "coverage_summary"
}

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_codeblock = prefix_matcher.codeblock_from_decl(M.view)

---Generate coverage summary as a Pandoc Table.
---@param data DataManager
---@param spec_id string
---@param options table|nil
---@return pandoc.Block
---Build link target, using cross-document .ext placeholder for objects in other specs.
local function make_link_target(pid, target_spec, current_spec)
    if target_spec == current_spec then
        return "#" .. pid
    else
        return target_spec .. ".ext#" .. pid
    end
end

function M.generate(data, spec_id, options)
    local rows_data = data:query_all([[
        SELECT
            sf.pid AS sf_pid,
            sf.title_text AS sf_title,
            sf.specification_ref AS sf_spec,
            COUNT(DISTINCT vc.id) AS vc_count,
            COUNT(DISTINCT CASE
                WHEN COALESCE(ev.key, av.string_value) = 'Pass'
                THEN vc.id
            END) AS passed
        FROM spec_objects sf
        LEFT JOIN spec_relations belongs
            ON belongs.target_object_id = sf.id AND belongs.type_ref = 'BELONGS'
        LEFT JOIN spec_objects hlr
            ON belongs.source_object_id = hlr.id AND hlr.type_ref = 'HLR'
        LEFT JOIN spec_relations verifies
            ON verifies.target_object_id = hlr.id
        LEFT JOIN spec_objects vc
            ON verifies.source_object_id = vc.id AND vc.type_ref = 'VC'
               AND vc.specification_ref = :spec_id
        LEFT JOIN spec_relations tr_vc
            ON tr_vc.target_object_id = vc.id
        LEFT JOIN spec_objects tr
            ON tr_vc.source_object_id = tr.id AND tr.type_ref = 'TR'
        LEFT JOIN spec_attribute_values av
            ON av.owner_object_id = tr.id AND av.name = 'result'
        LEFT JOIN enum_values ev
            ON av.enum_ref = ev.identifier
        WHERE sf.type_ref = 'SF'
          AND EXISTS (
              SELECT 1 FROM spec_relations b
              WHERE b.target_object_id = sf.id AND b.type_ref = 'BELONGS'
          )
        GROUP BY sf.id
        ORDER BY sf.pid
    ]], { spec_id = spec_id })

    local total_row = data:query_one([[
        SELECT
            COUNT(DISTINCT vc.id) AS total_vc,
            COUNT(DISTINCT CASE
                WHEN COALESCE(ev.key, av.string_value) = 'Pass'
                THEN vc.id
            END) AS total_passed
        FROM spec_objects vc
        LEFT JOIN spec_relations tr_vc
            ON tr_vc.target_object_id = vc.id
        LEFT JOIN spec_objects tr
            ON tr_vc.source_object_id = tr.id AND tr.type_ref = 'TR'
        LEFT JOIN spec_attribute_values av
            ON av.owner_object_id = tr.id AND av.name = 'result'
        LEFT JOIN enum_values ev
            ON av.enum_ref = ev.identifier
        WHERE vc.type_ref = 'VC'
          AND vc.specification_ref = :spec_id
    ]], { spec_id = spec_id })

    if not rows_data or #rows_data == 0 then
        return pandoc.Para({pandoc.Str("No Software Functions found.")})
    end

    local header = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Software Function")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VCs")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Passed")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Coverage")})})}
    }

    local body_rows = {}
    for _, row in ipairs(rows_data) do
        local vc_count = row.vc_count or 0
        local passed = row.passed or 0
        local coverage = vc_count > 0
            and string.format("%.0f%%", (passed / vc_count) * 100)
            or "—"

        local pid = row.sf_pid or ""
        local title = row.sf_title or ""
        local sf_href = make_link_target(pid, row.sf_spec or spec_id, spec_id)
        table.insert(body_rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(title)}, sf_href)})},
            {pandoc.Plain({pandoc.Str(tostring(vc_count))})},
            {pandoc.Plain({pandoc.Str(tostring(passed))})},
            {pandoc.Plain({pandoc.Str(coverage)})}
        })
    end

    -- Total row
    local total_vc = total_row and total_row.total_vc or 0
    local total_passed = total_row and total_row.total_passed or 0
    local total_coverage = total_vc > 0
        and string.format("%.0f%%", (total_passed / total_vc) * 100)
        or "—"

    table.insert(body_rows, {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Total")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str(tostring(total_vc))})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str(tostring(total_passed))})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str(total_coverage)})})}
    })

    local aligns = {
        pandoc.AlignLeft,
        pandoc.AlignCenter,
        pandoc.AlignCenter,
        pandoc.AlignCenter
    }
    local widths = {0, 0, 0, 0}

    local tbl = pandoc.SimpleTable({}, aligns, widths, header, body_rows)
    return pandoc.utils.from_simple_table(tbl)
end

M.handler = {
    name = "coverage_summary_handler",
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
