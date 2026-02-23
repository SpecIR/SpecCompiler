---Config-driven table formatting for DOCX postprocessors.
---Replaces duplicated fix_tables() in EMB/ABNT postprocessors.
---
---Supported config options:
---   skip_count      - number of tables to skip from the start (default 0)
---   borders         - uniform {style,sz,space,color} or per-side table
---   cell_margins    - {top,bottom,left,right} in dxa units
---   paragraph       - {zero_indent, compact_spacing, spacing}
---   header          - {shading, bold, remove_shading, cell_borders}
---
---@module table_formatter

local xml = require("infra.format.xml")
local M = {}

-- ============================================================================
-- Border Construction
-- ============================================================================

---Border side names in OOXML order.
local BORDER_SIDES = { "top", "left", "bottom", "right", "insideH", "insideV" }

---Map of logical side names to OOXML element names.
local SIDE_TO_ELEMENT = {
    top      = "w:top",
    left     = "w:left",
    bottom   = "w:bottom",
    right    = "w:right",
    insideH  = "w:insideH",
    inside_h = "w:insideH",
    insideV  = "w:insideV",
    inside_v = "w:insideV",
}

---Build a single border element from a side config.
---@param element_name string OOXML element name (e.g. "w:top")
---@param side_cfg table Border config with style, sz, space, color fields
---@return table XML node
local function build_border_side(element_name, side_cfg)
    if side_cfg.style == "nil" then
        -- Explicit "nil" means no border on this side (OOXML convention)
        return xml.node(element_name, {["w:val"] = "nil"})
    end
    return xml.node(element_name, {
        ["w:val"]   = side_cfg.style or "single",
        ["w:sz"]    = side_cfg.sz    or "4",
        ["w:space"] = side_cfg.space or "0",
        ["w:color"] = side_cfg.color or "000000",
    })
end

---Resolve border config for a given side.
---If the borders table contains per-side keys, use that; otherwise treat
---the entire table as uniform config for all sides.
---@param borders table Border configuration
---@param side string Logical side name (e.g. "top", "inside_h")
---@return table Side-specific border config
local function resolve_side_config(borders, side)
    -- Check for per-side config (support both insideH and inside_h naming)
    local per_side = borders[side]
    if per_side and type(per_side) == "table" then
        return per_side
    end
    -- Check underscore variant
    local underscore_side = side:gsub("(%u)", function(c) return "_" .. c:lower() end)
    per_side = borders[underscore_side]
    if per_side and type(per_side) == "table" then
        return per_side
    end
    -- Uniform config: the borders table itself is the config for every side
    return borders
end

---Create w:tblBorders node from config.
---@param borders table Border configuration (uniform or per-side)
---@return table XML node for w:tblBorders
local function create_borders(borders)
    local children = {}
    for _, side in ipairs(BORDER_SIDES) do
        local element_name = SIDE_TO_ELEMENT[side]
        local side_cfg = resolve_side_config(borders, side)
        table.insert(children, build_border_side(element_name, side_cfg))
    end
    return xml.node("w:tblBorders", {}, children)
end

-- ============================================================================
-- Cell Margins
-- ============================================================================

---Create w:tblCellMar node from config.
---@param margins table {top, bottom, left, right} values in dxa units
---@return table XML node for w:tblCellMar
local function create_cell_margins(margins)
    local children = {}
    if margins.top then
        table.insert(children, xml.node("w:top", {["w:w"] = margins.top, ["w:type"] = "dxa"}))
    end
    if margins.left then
        table.insert(children, xml.node("w:left", {["w:w"] = margins.left, ["w:type"] = "dxa"}))
    end
    if margins.bottom then
        table.insert(children, xml.node("w:bottom", {["w:w"] = margins.bottom, ["w:type"] = "dxa"}))
    end
    if margins.right then
        table.insert(children, xml.node("w:right", {["w:w"] = margins.right, ["w:type"] = "dxa"}))
    end
    return xml.node("w:tblCellMar", {}, children)
end

-- ============================================================================
-- Paragraph Formatting
-- ============================================================================

---Apply paragraph formatting to all paragraphs inside a table.
---@param tbl table Table DOM node
---@param para_cfg table Paragraph config
local function apply_paragraph_formatting(tbl, para_cfg)
    local paras = xml.find_by_name(tbl, "w:p")
    for _, p in ipairs(paras) do
        local pPr = xml.find_child(p, "w:pPr")
        if not pPr then
            pPr = xml.node("w:pPr")
            xml.insert_child(p, pPr, 1)
        end

        -- Zero indent: set firstLine, left, right to 0
        if para_cfg.zero_indent then
            local ind = xml.find_child(pPr, "w:ind")
            if not ind or xml.get_attr(ind, "w:firstLine") ~= "0" then
                xml.replace_child(pPr, "w:ind", xml.node("w:ind", {
                    ["w:firstLine"] = "0",
                    ["w:left"]      = "0",
                    ["w:right"]     = "0",
                }))
            end
        end

        -- Compact spacing: add spacing if not already present
        if para_cfg.compact_spacing then
            if not xml.find_child(pPr, "w:spacing") then
                local sp = para_cfg.spacing or {
                    before   = "40",
                    after    = "40",
                    line     = "240",
                    lineRule = "auto",
                }
                xml.add_child(pPr, xml.node("w:spacing", {
                    ["w:before"]   = sp.before   or "40",
                    ["w:after"]    = sp.after    or "40",
                    ["w:line"]     = sp.line     or "240",
                    ["w:lineRule"] = sp.lineRule  or "auto",
                }))
            end
        end
    end
end

-- ============================================================================
-- Header Row Formatting
-- ============================================================================

---Apply header formatting to rows marked with w:tblHeader.
---@param tbl table Table DOM node
---@param header_cfg table Header config
local function apply_header_formatting(tbl, header_cfg)
    local rows = xml.find_by_name(tbl, "w:tr")
    for _, tr in ipairs(rows) do
        local trPr = xml.find_child(tr, "w:trPr")
        if not trPr then goto continue end

        local tblHeader = xml.find_child(trPr, "w:tblHeader")
        if not tblHeader then goto continue end

        -- This is a header row - process its cells
        local cells = xml.find_children(tr, "w:tc")
        for _, tc in ipairs(cells) do
            local tcPr = xml.find_child(tc, "w:tcPr")
            if not tcPr then
                tcPr = xml.node("w:tcPr")
                xml.insert_child(tc, tcPr, 1)
            end

            -- Handle shading: either apply a fill color or remove existing shading
            if header_cfg.remove_shading then
                local shd = xml.find_child(tcPr, "w:shd")
                if shd then
                    xml.remove_child(tcPr, shd)
                end
            elseif header_cfg.shading then
                local shd = xml.find_child(tcPr, "w:shd")
                if shd then
                    xml.remove_child(tcPr, shd)
                end
                xml.add_child(tcPr, xml.node("w:shd", {
                    ["w:val"]   = "clear",
                    ["w:color"] = "auto",
                    ["w:fill"]  = header_cfg.shading,
                }))
            end

            -- Apply per-cell borders (e.g. ABNT midrule on header bottom)
            if header_cfg.cell_borders then
                local border_children = {}
                for side, cfg in pairs(header_cfg.cell_borders) do
                    local element_name = SIDE_TO_ELEMENT[side]
                    if element_name then
                        table.insert(border_children, build_border_side(element_name, cfg))
                    end
                end
                if #border_children > 0 then
                    xml.replace_child(tcPr, "w:tcBorders",
                        xml.node("w:tcBorders", {}, border_children))
                end
            end

            -- Bold text in header cells
            if header_cfg.bold then
                local header_paras = xml.find_by_name(tc, "w:p")
                for _, hp in ipairs(header_paras) do
                    local runs = xml.find_by_name(hp, "w:r")
                    for _, r in ipairs(runs) do
                        local rPr = xml.find_child(r, "w:rPr")
                        if not rPr then
                            rPr = xml.node("w:rPr")
                            xml.insert_child(r, rPr, 1)
                        end
                        if not xml.find_child(rPr, "w:b") then
                            xml.add_child(rPr, xml.node("w:b"))
                        end
                    end
                end
            end
        end

        ::continue::
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

---Format tables in document.xml using a config-driven approach.
---
---Parses the XML content, finds all w:tbl elements, skips the first
---`skip_count` tables, then applies borders, cell margins, paragraph
---formatting, and header treatment according to the provided config.
---
---@param content string document.xml content
---@param config table Table formatting configuration:
---   skip_count: number - tables to skip from start (default 0)
---   borders: table|nil - { style, sz, space, color } for all borders,
---       or per-side { top, bottom, left, right, insideH, insideV }
---       where each side is { style, sz, space, color }
---   cell_margins: table|nil - { top, bottom, left, right } in dxa units
---   paragraph: table|nil - { zero_indent: bool, compact_spacing: bool,
---       spacing: { before, after, line, lineRule } }
---   header: table|nil - { shading: string (fill color), bold: bool,
---       remove_shading: bool, cell_borders: table }
---@param log table Logger instance
---@return string Modified document.xml content
function M.format_tables(content, config, log)
    config = config or {}
    local skip_count = config.skip_count or 0

    local doc = xml.parse(content)
    if not doc or not doc.root then
        log.warn('[TABLE-FMT] Failed to parse document.xml')
        return content
    end

    local tables = xml.find_by_name(doc.root, "w:tbl")
    local start_index = skip_count + 1
    local formatted = 0

    for i = start_index, #tables do
        local tbl = tables[i]

        -- Ensure w:tblPr exists
        local tblPr = xml.find_child(tbl, "w:tblPr")
        if not tblPr then
            tblPr = xml.node("w:tblPr")
            xml.insert_child(tbl, tblPr, 1)
        end

        -- Apply table-level borders
        if config.borders then
            xml.replace_child(tblPr, "w:tblBorders", create_borders(config.borders))
        end

        -- Add cell margins if configured and not already present
        if config.cell_margins then
            if not xml.find_child(tblPr, "w:tblCellMar") then
                xml.add_child(tblPr, create_cell_margins(config.cell_margins))
            end
        end

        -- Apply paragraph formatting inside table cells
        if config.paragraph then
            apply_paragraph_formatting(tbl, config.paragraph)
        end

        -- Apply header row formatting
        if config.header then
            apply_header_formatting(tbl, config.header)
        end

        formatted = formatted + 1
    end

    if formatted > 0 then
        log.info('[TABLE-FMT] Formatted %d table(s) (skipped first %d)', formatted, skip_count)
    end

    return xml.serialize(doc)
end

---Format specific tables identified by caller (e.g. tables following a caption).
---Unlike format_tables() which skips by index, this applies config to an
---explicit list of table DOM nodes. The caller is responsible for parsing the
---document and selecting which tables to format.
---
---@param tbl table Single w:tbl DOM node to format
---@param config table Same config as format_tables() (borders, cell_margins, paragraph, header)
function M.format_table_node(tbl, config)
    config = config or {}

    -- Ensure w:tblPr exists
    local tblPr = xml.find_child(tbl, "w:tblPr")
    if not tblPr then
        tblPr = xml.node("w:tblPr")
        xml.insert_child(tbl, tblPr, 1)
    end

    -- Apply table-level borders
    if config.borders then
        xml.replace_child(tblPr, "w:tblBorders", create_borders(config.borders))
    end

    -- Add cell margins if configured and not already present
    if config.cell_margins then
        if not xml.find_child(tblPr, "w:tblCellMar") then
            xml.add_child(tblPr, create_cell_margins(config.cell_margins))
        end
    end

    -- Apply paragraph formatting
    if config.paragraph then
        apply_paragraph_formatting(tbl, config.paragraph)
    end

    -- Apply header row formatting
    if config.header then
        apply_header_formatting(tbl, config.header)
    end
end

return M
