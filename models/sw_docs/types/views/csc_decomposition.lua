---CSC Decomposition View for sw_docs.
---Generates a Pandoc Table showing all CSCs grouped by their parent Layer/Model CSC,
---with linked CSU lists per CSC. Uses path prefix matching for parent-child hierarchy
---and pandoc.Table with row_span for merged layer cells.
---
---Usage in markdown:
---  Inline syntax: `csc_decomposition:`
---  Code block syntax:
---    ```csc_decomposition
---    ```
---
---@module csc_decomposition

local M = {}

M.view = {
    id = "CSC_DECOMPOSITION",
    long_name = "CSC Decomposition",
    description = "CSC listing grouped by parent layer with CSU details",
    inline_prefix = "csc_decomposition"
}

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_codeblock = prefix_matcher.codeblock_from_decl(M.view)

---Build link target, using cross-document .ext placeholder for objects in other specs.
local function make_link_target(pid, target_spec, current_spec)
    if target_spec == current_spec then
        return "#" .. pid
    else
        return target_spec .. ".ext#" .. pid
    end
end

---Find the parent Layer/Model CSC for a Package CSC using path prefix matching.
local function find_parent_layer(csc, layers)
    local best = nil
    local best_len = 0
    local csc_path = csc.path or ""
    for _, layer in ipairs(layers) do
        local layer_path = layer.path or ""
        if layer_path ~= "" and csc_path:sub(1, #layer_path) == layer_path then
            if #layer_path > best_len then
                best = layer
                best_len = #layer_path
            end
        end
    end
    return best
end

---Build inline list of linked CSU titles.
local function build_csu_inlines(csus, spec_id)
    if not csus or #csus == 0 then
        return {pandoc.Str("—")}
    end
    local inlines = {}
    for i, csu in ipairs(csus) do
        if i > 1 then
            table.insert(inlines, pandoc.Str(", "))
        end
        local href = make_link_target(csu.pid, csu.spec or spec_id, spec_id)
        local label = csu.pid .. " " .. (csu.title or "")
        table.insert(inlines, pandoc.Link({pandoc.Str(label)}, href))
    end
    return inlines
end

---Create a pandoc.Cell with optional row/col span.
local function make_cell(content_inlines, rowspan, colspan)
    return pandoc.Cell(
        {pandoc.Plain(content_inlines)},
        pandoc.AlignDefault,
        rowspan or 1,
        colspan or 1
    )
end

---Generate CSC decomposition table as a Pandoc Table.
---Groups CSCs by parent Layer/Model with merged layer cells and linked CSU lists.
function M.generate(data, spec_id, options)
    -- Query all CSCs with their attributes
    local all_cscs = data:query_all([[
        SELECT
            csc.id,
            csc.pid,
            csc.title_text,
            csc.specification_ref,
            COALESCE(ev.key, ct_av.string_value, '') AS component_type,
            COALESCE(path_av.string_value, '') AS path,
            COALESCE(desc_av.string_value, '') AS description
        FROM spec_objects csc
        LEFT JOIN spec_attribute_values ct_av
            ON ct_av.owner_object_id = csc.id AND ct_av.name = 'component_type'
        LEFT JOIN enum_values ev
            ON ct_av.enum_ref = ev.identifier
        LEFT JOIN spec_attribute_values path_av
            ON path_av.owner_object_id = csc.id AND path_av.name = 'path'
        LEFT JOIN spec_attribute_values desc_av
            ON desc_av.owner_object_id = csc.id AND desc_av.name = 'description'
        WHERE csc.type_ref = 'CSC'
        ORDER BY csc.pid
    ]], {})

    if not all_cscs or #all_cscs == 0 then
        return pandoc.Para({pandoc.Str("No CSC objects found.")})
    end

    -- Query all CSUs grouped by their parent CSC (via traceability relation)
    local csu_rows = data:query_all([[
        SELECT
            target_csc.pid AS csc_pid,
            csu.pid AS csu_pid,
            csu.title_text AS csu_title,
            csu.specification_ref AS csu_spec
        FROM spec_objects csu
        JOIN spec_relations r
            ON r.source_object_id = csu.id
            AND r.source_attribute = 'traceability'
        JOIN spec_objects target_csc
            ON r.target_object_id = target_csc.id
            AND target_csc.type_ref = 'CSC'
        WHERE csu.type_ref = 'CSU'
        ORDER BY target_csc.pid, csu.pid
    ]], {})

    -- Group CSUs by parent CSC PID
    local csu_map = {}
    for _, row in ipairs(csu_rows or {}) do
        if not csu_map[row.csc_pid] then
            csu_map[row.csc_pid] = {}
        end
        table.insert(csu_map[row.csc_pid], { pid = row.csu_pid, title = row.csu_title, spec = row.csu_spec })
    end

    -- Separate Layer/Model CSCs from Package CSCs
    local layers = {}
    local packages = {}
    for _, csc in ipairs(all_cscs) do
        if csc.component_type == "Layer" or csc.component_type == "Model" then
            table.insert(layers, csc)
        else
            table.insert(packages, csc)
        end
    end

    -- Build hierarchy: group packages under their parent layer by path prefix
    local layer_children = {}
    for _, layer in ipairs(layers) do
        layer_children[layer.pid] = {}
    end
    for _, pkg in ipairs(packages) do
        local parent = find_parent_layer(pkg, layers)
        if parent then
            table.insert(layer_children[parent.pid], pkg)
        end
    end

    -- Column specs: 4 columns, all left-aligned, auto width
    local colspecs = {
        {pandoc.AlignLeft, nil},
        {pandoc.AlignLeft, nil},
        {pandoc.AlignLeft, nil},
        {pandoc.AlignLeft, nil}
    }

    -- Header row
    local header_row = pandoc.Row({
        make_cell({pandoc.Strong({pandoc.Str("Layer")})}),
        make_cell({pandoc.Strong({pandoc.Str("CSC")})}),
        make_cell({pandoc.Strong({pandoc.Str("CSUs")})}),
        make_cell({pandoc.Strong({pandoc.Str("Responsibility")})})
    })
    local thead = pandoc.TableHead({header_row})

    -- Body rows with merged layer cells via row_span
    local body_rows = {}
    for _, layer in ipairs(layers) do
        local pid = layer.pid or ""
        local children = layer_children[pid] or {}
        local href = make_link_target(pid, layer.specification_ref or spec_id, spec_id)
        local csus = csu_map[pid] or {}
        local span = 1 + #children  -- layer row + child rows

        -- First row of group: layer cell with row_span covering all children
        table.insert(body_rows, pandoc.Row({
            make_cell({pandoc.Strong({pandoc.Str(layer.title_text or "")})}, span, 1),
            make_cell({pandoc.Link({pandoc.Str(pid .. " " .. (layer.title_text or ""))}, href)}),
            make_cell(build_csu_inlines(csus, spec_id)),
            make_cell({pandoc.Str(layer.description or "")})
        }))

        -- Child rows: omit column 1 (covered by row_span from layer cell)
        for _, child in ipairs(children) do
            local cpid = child.pid or ""
            local chref = make_link_target(cpid, child.specification_ref or spec_id, spec_id)
            local child_csus = csu_map[cpid] or {}

            table.insert(body_rows, pandoc.Row({
                make_cell({pandoc.Link({pandoc.Str(cpid .. " " .. (child.title_text or ""))}, chref)}),
                make_cell(build_csu_inlines(child_csus, spec_id)),
                make_cell({pandoc.Str(child.description or "")})
            }))
        end
    end

    -- TableBody as plain Lua table (pandoc.TableBody constructor does not exist)
    local tbody = {
        attr = pandoc.Attr(),
        body = body_rows,
        head = {},
        row_head_columns = 0
    }

    return pandoc.Table(
        {long = {}, short = {}},
        colspecs,
        thead,
        {tbody},
        pandoc.TableFoot()
    )
end

M.handler = {
    name = "csc_decomposition_handler",
    prerequisites = {"spec_objects"},

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
