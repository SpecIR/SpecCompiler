---Native Pandoc Lua filter for HTML5 output.
---Converts speccompiler format markers to HTML for web output.
---
---This filter is compatible with pandoc --lua-filter for external CLI execution.
---
---Features:
---  - Converts RawBlock("speccompiler", "page-break") to HTML page-break div
---  - Converts RawBlock("speccompiler", "vertical-space:NNNN") to HTML spacer div
---  - Converts RawBlock("speccompiler", "bookmark-start:ID:NAME") to HTML anchor
---  - Converts RawBlock("speccompiler", "bookmark-end:ID") - removed (not needed in HTML)
---  - Converts RawBlock("speccompiler", "math-mathml:MATHML") to MathML
---  - Converts speccompiler-caption Div to HTML figure caption
---  - Converts speccompiler-numbered-equation Div to HTML equation with number
---  - Converts RawInline("speccompiler", "view:NAME:CONTENT") to HTML placeholder
---  - Converts semantic cover-* Divs to Bootstrap-compatible styled HTML
---
---@usage pandoc --lua-filter=html.lua -f json -t html5 input.json -o output.html
---@module models.default.filters.html
-- ============================================================================
-- HTML Templates
-- ============================================================================

---HTML for a page break.
local HTML_PAGE_BREAK = '<div class="page-break" style="page-break-after: always;"></div>'

---Convert twips to pixels.
---Formula: twips / 20 * 1.333 (1 twip = 1/20 point, 1 point ~= 1.333 pixels at 96 DPI)
---@param twips number Spacing in twips (1440 twips = 1 inch)
---@return number pixels Converted pixel value
local function twips_to_pixels(twips)
    return math.floor(twips / 20 * 1.333 + 0.5)
end

---Generate HTML for vertical spacing.
---@param twips number Spacing in twips (1440 twips = 1 inch)
---@return string HTML for spacer div
local function html_vertical_space(twips)
    local pixels = twips_to_pixels(twips)
    return string.format('<div class="spacer" style="height: %dpx;"></div>', pixels)
end

---Generate HTML anchor for bookmark.
---@param bm_id number Bookmark ID
---@param bm_name string Bookmark name
---@return string HTML anchor
local function html_bookmark(bm_id, bm_name)
    return string.format('<a id="%s" class="bookmark"></a>', bm_name)
end

---Generate HTML caption.
---Uses CSS counters for automatic numbering via data-counter attribute.
---@param prefix string Caption prefix (e.g., "Figure", "Table")
---@param counter_name string Counter name for CSS (e.g., "figure", "table")
---@param separator string Separator after number (e.g., ":", "-")
---@param caption string Caption text
---@param float_type string Float type for CSS class
---@return string HTML caption
local function html_caption(prefix, counter_name, separator, caption, float_type)
    local type_class = (float_type or "figure"):lower()
    local counter_lower = (counter_name or "figure"):lower()
    return string.format(
        '<figcaption class="caption caption-%s"><span class="caption-label">%s <span class="caption-num" data-counter="%s"></span>%s</span> %s</figcaption>',
        type_class, prefix, counter_lower, separator, caption
    )
end

---Generate HTML for numbered equation.
---@param mathml string MathML content
---@param seq_name string Equation label
---@param number string|number Equation number
---@param identifier string|nil Bookmark identifier
---@return string HTML for numbered equation
local function html_numbered_equation(mathml, seq_name, number, identifier)
    local id_attr = identifier and identifier ~= "" and string.format(' id="%s"', identifier) or ""
    -- MathML is natively supported by modern browsers
    local math_html = mathml and mathml ~= "" and mathml or '<span class="math-placeholder">[Equation]</span>'
    return string.format([[
<div class="equation-container"%s>
  <div class="equation-content">%s</div>
  <div class="equation-number">(%s)</div>
</div>]], id_attr, math_html, tostring(number or "1"))
end

-- ============================================================================
-- Cover Element Mapping
-- ============================================================================

---Mapping of cover-* classes to Bootstrap-compatible classes.
local COVER_CLASS_MAP = {
    ["cover-institution"] = "text-center fw-bold text-uppercase",
    ["cover-title"] = "text-center fs-1 fw-bold",
    ["cover-subtitle"] = "text-center fs-3",
    ["cover-author"] = "text-center",
    ["cover-authors"] = "text-center",
    ["cover-date"] = "text-center",
    ["cover-location"] = "text-center",
    ["cover-year"] = "text-center",
    ["cover-advisor"] = "text-center",
    ["cover-program"] = "text-center",
    ["cover-department"] = "text-center",
    ["cover-degree"] = "text-center",
    ["cover-docid"] = "text-center text-muted",
    ["cover-version"] = "text-center text-muted",
}

-- ============================================================================
-- Marker Parsing
-- ============================================================================

---Parse a speccompiler marker text.
---@param text string Marker text (e.g., "page-break", "vertical-space:1440")
---@return string marker_type Type of marker
---@return string|nil value Optional value for parameterized markers
local function parse_marker(text)
    local marker_type, value = text:match("^([^:]+):?(.*)$")
    if value == "" then
        value = nil
    end
    return marker_type, value
end

---Check if a Div has a specific class.
---@param div pandoc.Div The div to check
---@param class_name string Class name to look for
---@return boolean has_class True if div has the class
local function has_class(div, class_name)
    for _, c in ipairs(div.classes or {}) do
        if c == class_name then
            return true
        end
    end
    return false
end

---Get attribute value from Div.
---@param div pandoc.Div The div
---@param attr_name string Attribute name
---@return string|nil Attribute value
local function get_attr(div, attr_name)
    if div.attr and div.attr.attributes then
        return div.attr.attributes[attr_name]
    end
    return nil
end

---Check if a Div has any cover-* class.
---@param div pandoc.Div The div to check
---@return boolean has_cover_class True if div has a cover-* class
local function has_cover_class(div)
    for _, class in ipairs(div.classes) do
        if COVER_CLASS_MAP[class] then
            return true
        end
    end
    return false
end

-- ============================================================================
-- RawBlock Handler
-- ============================================================================

---Convert a speccompiler RawBlock to HTML.
---@param block pandoc.RawBlock The block to convert
---@return pandoc.RawBlock|nil Converted HTML block, or nil to remove
local function convert_speccompiler_block(block)
    local text = block.text

    -- Handle bookmark-start:ID:NAME
    local bm_id, bm_name = text:match("^bookmark%-start:(%d+):(.+)$")
    if bm_id and bm_name then
        return pandoc.RawBlock("html", html_bookmark(tonumber(bm_id), bm_name))
    end

    -- Handle bookmark-end:ID - not needed in HTML, just remove
    local end_id = text:match("^bookmark%-end:(%d+)$")
    if end_id then
        return {}
    end

    -- Handle math-mathml:MATHML (for HTML output - browsers support MathML)
    local mathml = text:match("^math%-mathml:(.+)$")
    if mathml then
        return pandoc.RawBlock("html", mathml)
    end

    -- Handle math-omml:OMML (skip for HTML - we prefer MathML)
    if text:match("^math%-omml:") then
        return {}  -- Remove - HTML uses MathML
    end

    -- Parse simple markers
    local marker_type, value = parse_marker(text)

    if marker_type == "page-break" then
        return pandoc.RawBlock("html", HTML_PAGE_BREAK)

    elseif marker_type == "vertical-space" then
        local twips = tonumber(value)
        if twips and twips > 0 then
            return pandoc.RawBlock("html", html_vertical_space(twips))
        else
            -- Default to 1 inch (1440 twips = 96px) if no valid value
            return pandoc.RawBlock("html", html_vertical_space(1440))
        end

    else
        -- Unknown speccompiler marker - remove
        return {}
    end
end

---Convert a speccompiler RawInline to HTML.
---@param inline pandoc.RawInline The inline to convert
---@return pandoc.RawInline|nil Converted HTML inline, or nil to remove
local function convert_speccompiler_inline(inline)
    local text = inline.text

    -- Handle inline-math-mathml:MATHML (for HTML output - browsers support MathML)
    local inline_mathml = text:match("^inline%-math%-mathml:(.+)$")
    if inline_mathml then
        return pandoc.RawInline("html", inline_mathml)
    end

    -- Handle inline-math-omml:OMML (skip for HTML - we prefer MathML)
    if text:match("^inline%-math%-omml:") then
        return {}  -- Remove - HTML uses MathML
    end

    -- Handle view:NAME:CONTENT - for HTML, return a placeholder
    local view_name, view_content = text:match("^view:([^:]+):(.+)$")
    if view_name and view_content then
        return pandoc.RawInline("html", string.format('<span class="view-placeholder">[%s]</span>', view_name))
    end

    -- Unknown inline marker - remove
    return {}
end

-- ============================================================================
-- Div Handlers
-- ============================================================================

---Convert speccompiler-caption Div to HTML.
---@param div pandoc.Div The caption div
---@return pandoc.RawBlock HTML caption
local function convert_caption_div(div)
    local seq_name = get_attr(div, "seq-name") or "FIGURE"
    local prefix = get_attr(div, "prefix") or "Figure"
    local separator = get_attr(div, "separator") or ":"
    local float_type = get_attr(div, "float-type") or "FIGURE"

    -- Extract caption text from Div content
    local caption = pandoc.utils.stringify(div.content)

    -- Use CSS counters for automatic numbering (seq_name determines counter)
    return pandoc.RawBlock("html", html_caption(prefix, seq_name, separator, caption, float_type))
end

---Convert speccompiler-numbered-equation Div to HTML.
---@param div pandoc.Div The equation div
---@return pandoc.RawBlock HTML numbered equation
local function convert_equation_div(div)
    local seq_name = get_attr(div, "seq-name") or "Equation"
    local number = get_attr(div, "number") or "1"
    local identifier = get_attr(div, "identifier") or ""

    -- Extract MathML from nested math-mathml RawBlock (prefer MathML for HTML)
    local mathml = ""
    for _, block in ipairs(div.content) do
        if block.t == "RawBlock" and block.format == "speccompiler" then
            local content = block.text:match("^math%-mathml:(.+)$")
            if content then
                mathml = content
                break
            end
        end
    end

    return pandoc.RawBlock("html", html_numbered_equation(mathml, seq_name, number, identifier))
end

---Convert speccompiler-table Div.
---Just unwrap the content - Pandoc handles table conversion.
---@param div pandoc.Div The table div
---@return table Content blocks
local function convert_table_div(div)
    -- Just return the content; Pandoc handles table-to-HTML conversion
    return div.content
end

---Convert a cover-* Div to styled HTML.
---@param div pandoc.Div The div to convert
---@return pandoc.Div Modified div with Bootstrap classes
local function convert_cover_div(div)
    local classes = div.classes

    for i, class in ipairs(classes) do
        local bootstrap_classes = COVER_CLASS_MAP[class]
        if bootstrap_classes then
            -- Remove the original cover-* class
            table.remove(classes, i)
            -- Add Bootstrap classes
            for bootstrap_class in bootstrap_classes:gmatch("%S+") do
                classes:insert(bootstrap_class)
            end
            break
        end
    end

    div.classes = classes
    return div
end

-- ============================================================================
-- Link Extension Replacement
-- ============================================================================

---Replace .ext placeholder with .html in cross-document links.
---@param link pandoc.Link The link to process
---@return pandoc.Link Modified link
local function replace_ext_placeholder(link)
    if link.target then
        link.target = link.target:gsub("%.ext#", ".html#")
        link.target = link.target:gsub("%.ext$", ".html")
    end
    return link
end

-- ============================================================================
-- TOC Stripping (direct block iteration)
-- ============================================================================

---Find speccompiler-toc Div, checking both direct and wrapped cases.
---Pandoc's sourcepos extension wraps blocks in Divs with data-pos attribute,
---so the speccompiler-toc Div may be nested inside a wrapper Div.
---@param block table A Pandoc block element
---@return boolean True if block is or wraps a speccompiler-toc Div
local function is_toc_block(block)
    if block.t ~= "Div" then return false end
    if has_class(block, "speccompiler-toc") then return true end
    local content = block.content or {}
    if #content == 1 and content[1].t == "Div" and has_class(content[1], "speccompiler-toc") then
        return true
    end
    return false
end

---Strip Header + speccompiler-toc Div pairs from the document.
---Uses direct block iteration because doc:walk() doesn't support
---Pandoc/Blocks handlers reliably across all execution contexts.
---@param doc table Pandoc document
---@return table Modified Pandoc document
local function strip_toc_blocks(doc)
    local blocks = doc.blocks
    local new_blocks = {}
    local i = 1
    while i <= #blocks do
        local block = blocks[i]
        -- Check for Header followed by speccompiler-toc Div (direct or wrapped)
        if block.t == "Header" and i < #blocks then
            if is_toc_block(blocks[i + 1]) then
                i = i + 2  -- Skip both Header and TOC Div
                goto continue
            end
        end
        -- Standalone speccompiler-toc Div (no preceding header)
        if is_toc_block(block) then
            i = i + 1
            goto continue
        end
        table.insert(new_blocks, block)
        i = i + 1
        ::continue::
    end
    return pandoc.Pandoc(new_blocks, doc.meta)
end

-- ============================================================================
-- Filter Tables
-- ============================================================================

-- State: tracks whether we are inside a cover section (to strip from HTML)
local in_cover_section = false

-- Pass 1: Div containers and cover-section markers.
-- Equation and caption Divs inspect inner speccompiler RawBlocks;
-- bottom-up traversal in a single pass would convert those RawBlocks
-- before the Div handler sees them, breaking extraction.
-- Cover-section markers (RawBlocks) are also handled here so that
-- the state flag is set before cover Divs are visited.
local FILTER_PASS1 = {
    RawBlock = function(block)
        if block.format == "speccompiler" then
            if block.text == "cover-section-start" then
                in_cover_section = true
                return {}
            elseif block.text == "cover-section-end" then
                in_cover_section = false
                return {}
            end
        end
        -- Strip any RawBlock inside the cover section (spacers, page breaks)
        if in_cover_section then
            return {}
        end
        return block
    end,

    Div = function(div)
        -- Strip all Divs inside a cover section
        if in_cover_section then
            return {}
        end
        if has_class(div, "speccompiler-caption") then
            return convert_caption_div(div)
        elseif has_class(div, "speccompiler-numbered-equation") then
            return convert_equation_div(div)
        elseif has_class(div, "speccompiler-table") then
            return convert_table_div(div)
        elseif has_cover_class(div) then
            return convert_cover_div(div)
        end
        -- Pass through other Divs unchanged
        return div
    end,
}

-- Pass 2: Individual elements (RawBlocks now safe to convert)
local FILTER_PASS2 = {
    RawBlock = function(block)
        if block.format == "speccompiler" then
            return convert_speccompiler_block(block)
        end
        -- Pass through other RawBlocks unchanged
        return block
    end,

    RawInline = function(inline)
        if inline.format == "speccompiler" then
            return convert_speccompiler_inline(inline)
        end
        -- Pass through other RawInlines unchanged
        return inline
    end,

    Link = function(link)
        return replace_ext_placeholder(link)
    end,

    Image = function(img)
        if img.src and not img.src:match("^%.%.")
                    and not img.src:match("^/")
                    and not img.src:match("^https?://")
                    and not img.src:match("^data:") then
            img.src = "../" .. img.src
        end
        return img
    end
}

-- ============================================================================
-- Module API (used by emitter via writer.load_filter)
-- ============================================================================

local M = {}

---Apply the HTML filter to a Pandoc document.
---@param doc table Pandoc document
---@param _config table Configuration (unused)
---@param _log table Logger (unused)
---@return table Modified Pandoc document
function M.apply(doc, _config, _log)
    doc = strip_toc_blocks(doc)
    in_cover_section = false
    return doc:walk(FILTER_PASS1):walk(FILTER_PASS2)
end

-- ============================================================================
-- Native Pandoc Filter (used when loaded via --lua-filter)
-- ============================================================================

if FORMAT then
    return {
        { Pandoc = function(doc) return strip_toc_blocks(doc) end },
        FILTER_PASS1,
        FILTER_PASS2
    }
end

return M
