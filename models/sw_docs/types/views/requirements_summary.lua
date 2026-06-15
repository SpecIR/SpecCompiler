local view_utils = require("pipeline.shared.view_utils")
local make_link_target = view_utils.make_link_target
---Requirements Summary View for sw_docs.
---Generates a Pandoc Table showing HLR counts grouped by Software Function (SF).
---
---Usage in markdown:
---  Code block syntax:
---    ```requirements_summary
---    ```
---
---@module requirements_summary

local schema = {
    id = "REQUIREMENTS_SUMMARY",
    extends = "TABLE_VIEW",
    long_name = "Requirements Summary",
    description = "HLR count grouped by Software Function",
    inline_prefix = "requirements_summary"
}


---Generate requirements summary as a Pandoc Table.
---@param params table|nil
---@param data DataManager
---@param spec_id string
---@return pandoc.Block
local function build_block(dctx)
    local data = dctx.data
    local spec_id = dctx.spec_id or "default"
    -- Fetch individual HLR PIDs per SF via BELONGS relation
    local rows_data = data:query_all([[
        SELECT
            sf.pid AS sf_pid,
            sf.title_text AS sf_title,
            sf.specification_ref AS sf_spec,
            hlr.pid AS hlr_pid,
            hlr.specification_ref AS hlr_spec
        FROM spec_objects sf
        LEFT JOIN spec_relations r
            ON r.target_object_id = sf.id AND r.type_ref = 'BELONGS'
        LEFT JOIN spec_objects hlr
            ON r.source_object_id = hlr.id AND hlr.type_ref = 'HLR'
        WHERE sf.type_ref = 'SF'
        ORDER BY sf.pid, hlr.pid
    ]], {})

    if not rows_data or #rows_data == 0 then
        return pandoc.Para({pandoc.Str("No Software Functions found.")})
    end

    -- Group HLR PIDs by SF
    local sf_order = {}
    local sf_map = {}
    for _, row in ipairs(rows_data) do
        local sf_pid = row.sf_pid or ""
        if not sf_map[sf_pid] then
            sf_map[sf_pid] = { title = row.sf_title or "", sf_spec = row.sf_spec, hlrs = {} }
            table.insert(sf_order, sf_pid)
        end
        if row.hlr_pid and row.hlr_pid ~= "" then
            table.insert(sf_map[sf_pid].hlrs, { pid = row.hlr_pid, spec = row.hlr_spec })
        end
    end

    local header = {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("SF ID")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Software Function")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Count")})})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Requirements")})})}
    }

    local body_rows = {}
    local total_count = 0
    for _, sf_pid in ipairs(sf_order) do
        local sf = sf_map[sf_pid]
        total_count = total_count + #sf.hlrs

        -- Build linked HLR inlines with cross-doc support
        local hlr_inlines = {}
        if #sf.hlrs > 0 then
            for i, hlr in ipairs(sf.hlrs) do
                if i > 1 then
                    table.insert(hlr_inlines, pandoc.Str(", "))
                end
                local hlr_href = make_link_target(hlr.pid, hlr.spec or spec_id, spec_id)
                table.insert(hlr_inlines, pandoc.Link({pandoc.Str(hlr.pid)}, hlr_href))
            end
        else
            hlr_inlines = {pandoc.Str("—")}
        end

        local sf_href = make_link_target(sf_pid, sf.sf_spec or spec_id, spec_id)
        table.insert(body_rows, {
            {pandoc.Plain({pandoc.Link({pandoc.Str(sf_pid)}, sf_href)})},
            {pandoc.Plain({pandoc.Str(sf.title)})},
            {pandoc.Plain({pandoc.Str(tostring(#sf.hlrs))})},
            {pandoc.Plain(hlr_inlines)}
        })
    end

    -- Total row
    table.insert(body_rows, {
        {pandoc.Plain({pandoc.Strong({pandoc.Str("Total")})})},
        {pandoc.Plain({pandoc.Str("")})},
        {pandoc.Plain({pandoc.Strong({pandoc.Str(tostring(total_count))})})},
        {pandoc.Plain({pandoc.Str("")})}
    })

    local aligns = {
        pandoc.AlignLeft,
        pandoc.AlignLeft,
        pandoc.AlignCenter,
        pandoc.AlignLeft
    }
    local widths = {0, 0, 0, 0}

    local tbl = pandoc.SimpleTable({}, aligns, widths, header, body_rows)
    return pandoc.utils.from_simple_table(tbl)
end

return {
    kind = "view",
    schema = schema,
    hooks = {
        build_block = build_block,
    }
}
