---Style Builder for SpecCompiler DOCX Generation.
---Provides unit conversion and OOXML style building functions.
---@module style_builder

local M = {}
local xml = require("infra.format.xml")

-- ============================================================================
-- Unit Conversion Functions
-- ============================================================================

---Convert measurement string to twips.
---1 inch = 1440 twips, 1 pt = 20 twips, 1 cm = 567 twips
---@param value string|number The measurement value (e.g., "1.3cm", "12pt", 24)
---@return integer twips
function M.to_twips(value)
    if type(value) == "number" then
        -- Assume points
        return math.floor(value * 20)
    end

    local num_str, unit = string.match(value, "^([%d.]+)(%a*)$")
    if not num_str then
        return 0
    end

    local num = tonumber(num_str) or 0
    unit = (unit or "pt"):lower()

    if unit == "cm" then
        return math.floor(num * 567)
    elseif unit == "mm" then
        return math.floor(num * 56.7)
    elseif unit == "in" then
        return math.floor(num * 1440)
    else
        -- Default to points
        return math.floor(num * 20)
    end
end

---Convert font size (pt) to half-points (Word uses half-points for w:sz).
---@param size number Font size in points
---@return string half_points
function M.to_half_points(size)
    return tostring(math.floor(size * 2))
end

---Convert line spacing ratio to OOXML line value.
---1.0 = 240, 1.5 = 360, 2.0 = 480
---@param ratio number Line spacing multiplier
---@return string line_value
function M.to_line_spacing(ratio)
    return tostring(math.floor(ratio * 240))
end

---Escape XML special characters.
---Delegates to xml.escape() for consistency.
---@param str string The string to escape
---@return string escaped
function M.escape_xml(str)
    return xml.escape(str)
end

-- ============================================================================
-- OOXML Style Building Functions
-- ============================================================================

---Built-in Word styles that should not be marked as custom.
M.BUILTIN_STYLES = {
    Normal = true,
    Heading1 = true,
    Heading2 = true,
    Heading3 = true,
    Heading4 = true,
    Heading5 = true,
    Heading6 = true,
    Heading7 = true,
    Heading8 = true,
    Heading9 = true,
    Title = true,
    Subtitle = true,
    Quote = true,
    Caption = true,
    Bibliography = true,
    TOC1 = true,
    TOC2 = true,
    TOC3 = true,
    TOC4 = true,
    TOC5 = true,
    BodyText = true,
    FirstParagraph = true,
    FootnoteText = true,
    FootnoteReference = true,
    Hyperlink = true,
    ListParagraph = true,
}

---Build run properties XML (w:rPr) from style config.
---@param style table The style definition
---@return string xml The rPr XML element or empty string
function M.build_rPr(style)
    local font = style.font
    if not font and not style.lang then
        return ""
    end

    local children = {}

    -- Font family
    if font and font.name then
        table.insert(children, xml.node("w:rFonts", {
            ["w:ascii"] = font.name,
            ["w:hAnsi"] = font.name,
            ["w:cs"] = font.name,
            ["w:eastAsia"] = font.name,
        }))
    end

    -- Bold
    if font and font.bold then
        table.insert(children, xml.node("w:b"))
        table.insert(children, xml.node("w:bCs"))
    end

    -- Italic
    if font and font.italic then
        table.insert(children, xml.node("w:i"))
        table.insert(children, xml.node("w:iCs"))
    end

    -- All caps
    if font and font.all_caps then
        table.insert(children, xml.node("w:caps"))
    end

    -- Small caps
    if font and font.small_caps then
        table.insert(children, xml.node("w:smallCaps"))
    end

    -- Underline
    if font and font.underline then
        table.insert(children, xml.node("w:u", { ["w:val"] = "single" }))
    end

    -- Strikethrough
    if font and font.strike then
        table.insert(children, xml.node("w:strike"))
    end

    -- Font size
    if font and font.size then
        local sz = M.to_half_points(font.size)
        table.insert(children, xml.node("w:sz", { ["w:val"] = sz }))
        table.insert(children, xml.node("w:szCs", { ["w:val"] = sz }))
    end

    -- Font color
    if font and font.color then
        table.insert(children, xml.node("w:color", { ["w:val"] = font.color }))
    end

    -- Language override
    if style.lang then
        table.insert(children, xml.node("w:lang", { ["w:val"] = style.lang }))
    end

    if #children == 0 then
        return ""
    end

    return xml.serialize_element(xml.node("w:rPr", nil, children))
end

---Build paragraph properties XML (w:pPr) from style config.
---NOTE: Heading numbering (numPr) is NOT added here - it's handled by the ABNT
---postprocessor which adds numPr per-paragraph.
---@param style table The style definition
---@return string xml The pPr XML element or empty string
function M.build_pPr(style)
    local children = {}

    -- Widow/orphan control
    if style.widow_control ~= false then
        table.insert(children, xml.node("w:widowControl"))
    end

    -- Keep with next
    if style.keep_next then
        table.insert(children, xml.node("w:keepNext"))
    end

    -- Keep lines together
    if style.keep_lines then
        table.insert(children, xml.node("w:keepLines"))
    end

    -- Page break before
    if style.page_break_before then
        table.insert(children, xml.node("w:pageBreakBefore"))
    end

    -- Spacing
    if style.spacing then
        local attrs = {}
        if style.spacing.before ~= nil then
            attrs["w:before"] = tostring(M.to_twips(style.spacing.before))
        end
        if style.spacing.after ~= nil then
            attrs["w:after"] = tostring(M.to_twips(style.spacing.after))
        end
        if style.spacing.line ~= nil then
            attrs["w:line"] = M.to_line_spacing(style.spacing.line)
            attrs["w:lineRule"] = "auto"
        end
        if next(attrs) then
            table.insert(children, xml.node("w:spacing", attrs))
        end
    end

    -- Indentation
    if style.indent then
        local attrs = {}
        if style.indent.first_line then
            attrs["w:firstLine"] = tostring(M.to_twips(style.indent.first_line))
        end
        if style.indent.left then
            attrs["w:left"] = tostring(M.to_twips(style.indent.left))
        end
        if style.indent.right then
            attrs["w:right"] = tostring(M.to_twips(style.indent.right))
        end
        if style.indent.hanging then
            attrs["w:hanging"] = tostring(M.to_twips(style.indent.hanging))
        end
        if next(attrs) then
            table.insert(children, xml.node("w:ind", attrs))
        end
    end

    -- Paragraph borders (pBdr)
    if style.borders then
        local border_children = {}
        local function add_border(name, border)
            if border and border.style ~= "none" then
                local attrs = {
                    ["w:val"] = border.style or "single",
                    ["w:sz"] = tostring(math.floor((border.width or 0.5) * 8)),
                    ["w:space"] = tostring(border.space or 1),
                    ["w:color"] = border.color or "000000",
                }
                table.insert(border_children, xml.node("w:" .. name, attrs))
            end
        end
        add_border("top", style.borders.top)
        add_border("bottom", style.borders.bottom)
        add_border("left", style.borders.left)
        add_border("right", style.borders.right)
        if #border_children > 0 then
            table.insert(children, xml.node("w:pBdr", nil, border_children))
        end
    end

    -- Paragraph shading (shd)
    if style.shading then
        table.insert(children, xml.node("w:shd", {
            ["w:val"] = style.shading.pattern or "clear",
            ["w:color"] = style.shading.color or "auto",
            ["w:fill"] = style.shading.fill or "auto",
        }))
    end

    -- Alignment
    if style.alignment then
        local align = style.alignment
        if align == "justified" then
            align = "both"
        end
        table.insert(children, xml.node("w:jc", { ["w:val"] = align }))
    end

    -- Outline level (for headings)
    if style.outline_level ~= nil then
        table.insert(children, xml.node("w:outlineLvl", { ["w:val"] = tostring(style.outline_level) }))
    end

    if #children == 0 then
        return ""
    end

    return xml.serialize_element(xml.node("w:pPr", nil, children))
end

---Build a complete style XML element from config.
---@param style table The style definition with id, name, font, spacing, etc.
---@return string xml The complete w:style element
function M.build_style_xml(style)
    local is_custom = not M.BUILTIN_STYLES[style.id]

    local style_attrs = {
        ["w:type"] = "paragraph",
        ["w:styleId"] = style.id,
    }
    if is_custom then
        style_attrs["w:customStyle"] = "1"
    end

    local children = {}

    -- Style name
    table.insert(children, xml.node("w:name", { ["w:val"] = style.name }))

    -- Based on
    if style.based_on then
        table.insert(children, xml.node("w:basedOn", { ["w:val"] = style.based_on }))
    end

    -- Next style
    if style.next then
        table.insert(children, xml.node("w:next", { ["w:val"] = style.next }))
    end

    -- Quick format (show in style gallery)
    table.insert(children, xml.node("w:qFormat"))

    -- UI priority
    table.insert(children, xml.node("w:uiPriority", { ["w:val"] = "99" }))

    -- Paragraph properties
    local pPr = M.build_pPr(style)
    if pPr ~= "" then
        table.insert(children, xml.raw(pPr))
    end

    -- Run properties
    local rPr = M.build_rPr(style)
    if rPr ~= "" then
        table.insert(children, xml.raw(rPr))
    end

    return xml.serialize_element(xml.node("w:style", style_attrs, children))
end

---Build character style XML element.
---@param style table The character style definition
---@return string xml The complete w:style element
function M.build_character_style_xml(style)
    local is_custom = not M.BUILTIN_STYLES[style.id]

    local style_attrs = {
        ["w:type"] = "character",
        ["w:styleId"] = style.id,
    }
    if is_custom then
        style_attrs["w:customStyle"] = "1"
    end

    local children = {}

    -- Style name
    table.insert(children, xml.node("w:name", { ["w:val"] = style.name }))

    -- Based on
    if style.based_on then
        table.insert(children, xml.node("w:basedOn", { ["w:val"] = style.based_on }))
    end

    -- Link to paragraph style (for linked char styles like Heading1Char)
    if style.link then
        table.insert(children, xml.node("w:link", { ["w:val"] = style.link }))
    end

    -- Quick format
    table.insert(children, xml.node("w:qFormat"))

    -- UI priority
    table.insert(children, xml.node("w:uiPriority", { ["w:val"] = "99" }))

    -- Run properties (character styles only have rPr)
    local rPr = M.build_rPr(style)
    if rPr ~= "" then
        table.insert(children, xml.raw(rPr))
    end

    return xml.serialize_element(xml.node("w:style", style_attrs, children))
end

---Build table style XML element.
---@param style table The table style definition
---@return string xml The complete w:style element
function M.build_table_style_xml(style)
    local style_attrs = {
        ["w:type"] = "table",
        ["w:styleId"] = style.id,
        ["w:customStyle"] = "1",
    }

    local children = {}

    -- Style name
    table.insert(children, xml.node("w:name", { ["w:val"] = style.name }))

    -- Quick format
    table.insert(children, xml.node("w:qFormat"))

    -- UI priority
    table.insert(children, xml.node("w:uiPriority", { ["w:val"] = "99" }))

    -- Table properties
    local tbl_children = {}

    -- Table borders
    if style.borders then
        local border_children = {}
        local function add_border(name, border)
            if border and border.style ~= "none" then
                table.insert(border_children, xml.node("w:" .. name, {
                    ["w:val"] = border.style,
                    ["w:sz"] = tostring(math.floor(border.width * 8)),
                    ["w:color"] = border.color,
                }))
            end
        end
        add_border("top", style.borders.top)
        add_border("bottom", style.borders.bottom)
        add_border("left", style.borders.left)
        add_border("right", style.borders.right)
        add_border("insideH", style.borders.inside_h or style.borders.insideH)
        add_border("insideV", style.borders.inside_v or style.borders.insideV)

        if #border_children > 0 then
            table.insert(tbl_children, xml.node("w:tblBorders", nil, border_children))
        end
    end

    -- Cell margins
    if style.cell_margins then
        local margin_children = {}
        if style.cell_margins.top then
            table.insert(margin_children, xml.node("w:top", {
                ["w:w"] = tostring(M.to_twips(style.cell_margins.top)),
                ["w:type"] = "dxa",
            }))
        end
        if style.cell_margins.bottom then
            table.insert(margin_children, xml.node("w:bottom", {
                ["w:w"] = tostring(M.to_twips(style.cell_margins.bottom)),
                ["w:type"] = "dxa",
            }))
        end
        if style.cell_margins.left then
            table.insert(margin_children, xml.node("w:left", {
                ["w:w"] = tostring(M.to_twips(style.cell_margins.left)),
                ["w:type"] = "dxa",
            }))
        end
        if style.cell_margins.right then
            table.insert(margin_children, xml.node("w:right", {
                ["w:w"] = tostring(M.to_twips(style.cell_margins.right)),
                ["w:type"] = "dxa",
            }))
        end
        if #margin_children > 0 then
            table.insert(tbl_children, xml.node("w:tblCellMar", nil, margin_children))
        end
    end

    if #tbl_children > 0 then
        table.insert(children, xml.node("w:tblPr", nil, tbl_children))
    end

    -- Table conditional formatting: header row (tblStylePr type="firstRow")
    if style.header_row then
        local hr_children = {}

        -- Header row paragraph properties (bold, etc.)
        if style.header_row.font then
            local rPr_children = {}
            if style.header_row.font.bold then
                table.insert(rPr_children, xml.node("w:b"))
                table.insert(rPr_children, xml.node("w:bCs"))
            end
            if #rPr_children > 0 then
                table.insert(hr_children, xml.node("w:rPr", nil, rPr_children))
            end
        end

        -- Header row shading
        if style.header_row.shading then
            local tc_children = {
                xml.node("w:shd", {
                    ["w:val"] = style.header_row.shading.pattern or "clear",
                    ["w:color"] = style.header_row.shading.color or "auto",
                    ["w:fill"] = style.header_row.shading.fill or "auto",
                })
            }
            table.insert(hr_children, xml.node("w:tcPr", nil, tc_children))
        end

        if #hr_children > 0 then
            table.insert(children, xml.node("w:tblStylePr", { ["w:type"] = "firstRow" }, hr_children))
        end
    end

    return xml.serialize_element(xml.node("w:style", style_attrs, children))
end

return M
