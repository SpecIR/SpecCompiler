---Test Execution Matrix View for sw_docs.
---Generates a deterministic VC -> HLR -> method matrix from SpecIR.

local M = {}

M.view = {
    id = "TEST_EXECUTION_MATRIX",
    long_name = "Test Execution Matrix",
    description = "Executable verification procedure matrix for VC coverage",
    inline_prefix = "test_execution_matrix"
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

---Generate test execution matrix as a Pandoc Table.
---@param data DataManager
---@param spec_id string
---@param options table|nil
---@return pandoc.Block
function M.generate(data, spec_id, options)
    local vcs = data:query_all([[
        SELECT id, pid, title_text
        FROM spec_objects
        WHERE type_ref = 'VC'
          AND specification_ref = :spec_id
        ORDER BY pid
    ]], { spec_id = spec_id }) or {}

    if #vcs == 0 then
        return pandoc.Para({pandoc.Str("No VC entries found for execution matrix generation.")})
    end

    local rows = {}
    for _, vc in ipairs(vcs) do
        local hlrs = data:query_all([[
            SELECT DISTINCT h.pid, h.specification_ref AS hlr_spec
            FROM spec_relations r
            JOIN spec_objects h ON h.id = r.target_object_id
            WHERE r.source_object_id = :vc_id
              AND h.type_ref = 'HLR'
            ORDER BY h.pid
        ]], { vc_id = vc.id }) or {}

        local hlr_inlines = {}
        if #hlrs > 0 then
            for i, row in ipairs(hlrs) do
                if row.pid and row.pid ~= "" then
                    if i > 1 then
                        table.insert(hlr_inlines, pandoc.Str(", "))
                    end
                    local href = make_link_target(row.pid, row.hlr_spec or spec_id, spec_id)
                    table.insert(hlr_inlines, pandoc.Link({pandoc.Str(row.pid)}, href))
                end
            end
        end
        if #hlr_inlines == 0 then
            hlr_inlines = {pandoc.Str("-")}
        end

        -- Query verification_method attribute
        local vm_attr = data:query_one([[
            SELECT COALESCE(ev.key, av.string_value) AS method
            FROM spec_attribute_values av
            LEFT JOIN enum_values ev ON av.enum_ref = ev.identifier
            WHERE av.owner_object_id = :owner
              AND av.name = 'verification_method'
            LIMIT 1
        ]], { owner = vc.id })
        local verification_method = vm_attr and vm_attr.method or "-"

        local vc_label = vc.pid or vc.title_text or vc.id

        table.insert(rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(vc_label or "-")}, "#" .. (vc_label or "-"))})},
            {pandoc.Plain(hlr_inlines)},
            {pandoc.Plain({pandoc.Str(verification_method)})},
        })
    end

    local header = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("VC ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("HLR")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Method")})})},
    }

    local aligns = { pandoc.AlignLeft, pandoc.AlignLeft, pandoc.AlignCenter }
    local widths = {0, 0, 0}

    local tbl = pandoc.SimpleTable({}, aligns, widths, header, rows)
    return pandoc.utils.from_simple_table(tbl)
end

M.handler = {
    name = "test_execution_matrix_handler",
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
