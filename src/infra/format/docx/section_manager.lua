---Config-driven OOXML section management for DOCX postprocessors.
---Extracts generic section operations (section breaks, sectPr construction,
---header/footer wiring, positioned float handling) into a shared library.
---
---Callers provide configuration tables describing page layout, margins,
---header/footer references, and page numbering; this module handles all
---XML construction and document.xml manipulation.
---@module section_manager

local xml = require("infra.format.xml")

local M = {}

-- ============================================================================
-- Header/Footer Relationship Extraction
-- ============================================================================

---Extract header/footer relationship IDs from document.xml.rels content.
---@param rels_content string The XML content of document.xml.rels
---@param expected string[] Array of target filenames (e.g. {"header1.xml", "header2.xml"})
---@return table|nil Mapping of filename stem to rId string, or nil if any expected target is missing
function M.extract_header_ids(rels_content, expected)
    local ids = {}
    -- Match each Relationship element, then extract Id and Target independently
    -- (XML attribute order is not guaranteed)
    for rel in rels_content:gmatch('<Relationship[^>]+>') do
        local rid = rel:match('Id="(rId%d+)"')
        local target = rel:match('Target="(header%d%.xml)"')
        if rid and target then
            local stem = target:match("^(.+)%.xml$")
            if stem then
                ids[stem] = rid
            end
        end
    end
    -- Verify all expected targets were found
    for _, filename in ipairs(expected) do
        local stem = filename:match("^(.+)%.xml$")
        if not stem or not ids[stem] then
            return nil
        end
    end
    return ids
end

-- ============================================================================
-- Style Position Search
-- ============================================================================

---Find the position of the first paragraph that has one of the given pStyle values.
---@param content string document.xml content
---@param styles table Lookup table like {["Heading1"]=true, ["Heading2"]=true}
---@return number|nil Start position of the `<w:p` tag, or nil if not found
function M.find_first_style_position(content, styles)
    local search_start = 1
    while true do
        local p_start = content:find("<w:p[>%s]", search_start)
        if not p_start then
            return nil
        end
        -- Find the end of this paragraph
        local p_end = content:find("</w:p>", p_start)
        if not p_end then
            return nil
        end
        -- Extract paragraph content
        local para = content:sub(p_start, p_end + 5)
        -- Check for pStyle
        local style_val = para:match('<w:pStyle%s+w:val="([^"]+)"')
        if style_val and styles[style_val] then
            return p_start
        end
        search_start = p_end + 6
    end
end

-- ============================================================================
-- Section Properties Construction
-- ============================================================================

---Build a <w:sectPr> XML string from a config table.
---
---Child elements are added in OOXML-compliant order:
---headerReference, footerReference, pgSz, pgMar, pgNumType, cols, type,
---titlePg, docGrid.
---
---@param config table Section properties configuration:
---  headers: array of {type, rid} for headerReference elements
---  footers: array of {type, rid} for footerReference elements
---  page_size: {w, h, orient} — orient is optional
---  margins: {top, right, bottom, left, header, footer, gutter}
---  page_numbering: {fmt, start} — start is optional
---  cols: {space} — optional
---  title_pg: boolean — optional, adds <w:titlePg/>
---  doc_grid: {line_pitch} — optional
---  section_type: string — optional, adds <w:type w:val="..."/>
---@return string Serialized <w:sectPr>...</w:sectPr> XML
function M.build_section_properties(config)
    local children = {}

    -- headerReference elements
    if config.headers then
        for _, h in ipairs(config.headers) do
            children[#children + 1] = xml.node("w:headerReference", {
                ["w:type"] = h.type,
                ["r:id"]   = h.rid,
            })
        end
    end

    -- footerReference elements
    if config.footers then
        for _, f in ipairs(config.footers) do
            children[#children + 1] = xml.node("w:footerReference", {
                ["w:type"] = f.type,
                ["r:id"]   = f.rid,
            })
        end
    end

    -- pgSz
    if config.page_size then
        local attrs = {
            ["w:w"] = config.page_size.w,
            ["w:h"] = config.page_size.h,
        }
        if config.page_size.orient then
            attrs["w:orient"] = config.page_size.orient
        end
        children[#children + 1] = xml.node("w:pgSz", attrs)
    end

    -- pgMar
    if config.margins then
        children[#children + 1] = xml.node("w:pgMar", {
            ["w:top"]    = config.margins.top,
            ["w:right"]  = config.margins.right,
            ["w:bottom"] = config.margins.bottom,
            ["w:left"]   = config.margins.left,
            ["w:header"] = config.margins.header,
            ["w:footer"] = config.margins.footer,
            ["w:gutter"] = config.margins.gutter,
        })
    end

    -- pgNumType
    if config.page_numbering then
        local attrs = {
            ["w:fmt"] = config.page_numbering.fmt,
        }
        if config.page_numbering.start then
            attrs["w:start"] = config.page_numbering.start
        end
        children[#children + 1] = xml.node("w:pgNumType", attrs)
    end

    -- cols
    if config.cols then
        children[#children + 1] = xml.node("w:cols", {
            ["w:space"] = config.cols.space,
        })
    end

    -- type (section type)
    if config.section_type then
        children[#children + 1] = xml.node("w:type", {
            ["w:val"] = config.section_type,
        })
    end

    -- titlePg
    if config.title_pg then
        children[#children + 1] = xml.node("w:titlePg")
    end

    -- docGrid
    if config.doc_grid then
        children[#children + 1] = xml.node("w:docGrid", {
            ["w:linePitch"] = config.doc_grid.line_pitch,
        })
    end

    local sectpr = xml.node("w:sectPr", nil, children)
    return xml.serialize_element(sectpr)
end

-- ============================================================================
-- Section Break Injection
-- ============================================================================

---Inject a section break into the paragraph immediately BEFORE the given position.
---The sectPr is inserted into the previous paragraph's w:pPr element.
---
---@param content string document.xml content
---@param position number Start position of the target paragraph (first paragraph of the NEW section)
---@param sectpr string The <w:sectPr>...</w:sectPr> XML to inject
---@param log table Logger instance
---@return string Modified content
function M.inject_section_break(content, position, sectpr, log)
    -- Search backwards from position to find the previous </w:p> tag
    local prev_p_end = content:sub(1, position - 1):find("</w:p>[^<]*$")
    if not prev_p_end then
        -- Try reverse search: find the last </w:p> before position
        local last_end = nil
        local s = 1
        while true do
            local found = content:find("</w:p>", s)
            if not found or found >= position then
                break
            end
            last_end = found
            s = found + 1
        end
        prev_p_end = last_end
    end

    if not prev_p_end then
        log.warn("[SECTION-MGR] Could not find previous paragraph for section break injection")
        return content
    end

    -- Find the start of that previous paragraph
    local prev_p_start = nil
    local s = 1
    while true do
        local found = content:find("<w:p[>%s]", s)
        if not found or found > prev_p_end then
            break
        end
        prev_p_start = found
        s = found + 1
    end

    if not prev_p_start then
        log.warn("[SECTION-MGR] Could not find start of previous paragraph for section break injection")
        return content
    end

    -- Extract the full previous paragraph
    local para_close_end = prev_p_end + #"</w:p>" - 1
    local prev_para = content:sub(prev_p_start, para_close_end)

    -- Extract paragraph text for logging
    local para_text = prev_para:gsub("<[^>]+>", ""):sub(1, 60)
    log.debug("[SECTION-MGR] Injecting section break into paragraph: '%s'", para_text)

    -- Modify the paragraph to include sectPr
    local modified_para
    local ppr_end = prev_para:find("</w:pPr>")
    if ppr_end then
        -- Insert sectpr before </w:pPr>
        modified_para = prev_para:sub(1, ppr_end - 1) .. sectpr .. prev_para:sub(ppr_end)
    else
        -- No <w:pPr> exists — create one after the opening <w:p...> tag
        local open_tag_end = prev_para:find(">")
        if not open_tag_end then
            log.warn("[SECTION-MGR] Malformed paragraph element, cannot inject section break")
            return content
        end
        modified_para = prev_para:sub(1, open_tag_end)
            .. "<w:pPr>" .. sectpr .. "</w:pPr>"
            .. prev_para:sub(open_tag_end + 1)
    end

    -- Replace original paragraph with modified version
    return content:sub(1, prev_p_start - 1) .. modified_para .. content:sub(para_close_end + 1)
end

-- ============================================================================
-- Body sectPr Replacement
-- ============================================================================

---Replace only the LAST <w:sectPr>...</w:sectPr> in the document.
---Iterates to find ALL sectPr positions and replaces only the final one,
---avoiding Lua's non-greedy `.-` matching issues across multiple sectPr elements.
---
---@param content string document.xml content
---@param new_sectpr string Replacement sectPr XML
---@return string Modified content
---@return boolean True if replacement was made
function M.replace_body_sectpr(content, new_sectpr)
    -- Find ALL <w:sectPr positions, keep the last one
    local last_start = nil
    local s = 1
    while true do
        local found = content:find("<w:sectPr[>%s]", s)
        if not found then
            break
        end
        last_start = found
        s = found + 1
    end

    if not last_start then
        return content, false
    end

    -- Find matching </w:sectPr> after the last opening
    local close_start, close_end = content:find("</w:sectPr>", last_start)
    if not close_start then
        return content, false
    end

    -- Replace that span with new_sectpr
    return content:sub(1, last_start - 1) .. new_sectpr .. content:sub(close_end + 1), true
end

-- ============================================================================
-- Positioned Float Section Handling
-- ============================================================================

---Replace positioned float section markers with full sectPr containing header references.
---
---Performs a 3-pass transformation:
---  1. Find all specdown:sectPr markers and track landscape positions
---  2. (Optional) Upscale images in landscape sections to fill content area
---  3. Replace marker + minimal sectPr paragraph with full sectPr paragraph
---
---@param content string document.xml content
---@param section_builder function Callback: function(orientation) -> string sectPr XML
---@param log table Logger instance
---@param image_scaling table|nil Image scaling config: {width_emu=N, height_emu=N}
---@return string Modified content
function M.fix_positioned_float_sections(content, section_builder, log, image_scaling)
    -- Pass 1: Find all specdown:sectPr markers and track landscape positions
    local marker_pattern = '<!%-%- specdown:sectPr:(%w+) %-%->'
    local landscape_positions = {}
    local marker_count = 0

    local s = 1
    while true do
        local m_start, m_end, orientation = content:find(marker_pattern, s)
        if not m_start then
            break
        end
        marker_count = marker_count + 1
        if orientation == "landscape" then
            landscape_positions[#landscape_positions + 1] = m_start
        end
        s = m_end + 1
    end

    log.debug("[SECTION-MGR] Found %d section markers (%d landscape)", marker_count, #landscape_positions)

    if marker_count == 0 then
        return content
    end

    -- Pass 2: Upscale images in landscape sections (only if image_scaling provided)
    if image_scaling and #landscape_positions > 0 then
        local target_w = image_scaling.width_emu
        local target_h = image_scaling.height_emu
        local scaled_count = 0

        for _, lpos in ipairs(landscape_positions) do
            -- Search backward up to 5000 chars for the last wp:extent element
            local search_start = math.max(1, lpos - 5000)
            local search_region = content:sub(search_start, lpos - 1)

            -- Find the last wp:extent in the search region
            local last_ext_pos = nil
            local ext_s = 1
            while true do
                local found = search_region:find('<wp:extent ', ext_s)
                if not found then
                    break
                end
                last_ext_pos = found
                ext_s = found + 1
            end

            if last_ext_pos then
                -- Convert to absolute position in content
                local abs_pos = search_start + last_ext_pos - 1

                -- Extract the wp:extent element
                local ext_tag_end = content:find("/>", abs_pos)
                if ext_tag_end then
                    local ext_tag = content:sub(abs_pos, ext_tag_end + 1)
                    local cx = tonumber(ext_tag:match('cx="(%d+)"'))
                    local cy = tonumber(ext_tag:match('cy="(%d+)"'))

                    if cx and cy and cx > 0 and cy > 0 then
                        -- Calculate scale to fit within content area (only upscale)
                        local scale_x = target_w / cx
                        local scale_y = target_h / cy
                        local scale = math.min(scale_x, scale_y)

                        if scale > 1 then
                            local new_cx = math.floor(cx * scale)
                            local new_cy = math.floor(cy * scale)

                            -- Replace wp:extent dimensions
                            local new_ext_tag = ext_tag:gsub('cx="%d+"', 'cx="' .. new_cx .. '"')
                            new_ext_tag = new_ext_tag:gsub('cy="%d+"', 'cy="' .. new_cy .. '"')
                            content = content:sub(1, abs_pos - 1) .. new_ext_tag .. content:sub(ext_tag_end + 2)

                            -- Also find and replace the corresponding a:ext element nearby
                            -- Search forward from the wp:extent position for a:ext
                            local a_ext_start = content:find('<a:ext ', abs_pos)
                            if a_ext_start and a_ext_start < abs_pos + 2000 then
                                local a_ext_end = content:find("/>", a_ext_start)
                                if a_ext_end then
                                    local a_ext_tag = content:sub(a_ext_start, a_ext_end + 1)
                                    local new_a_ext = a_ext_tag:gsub('cx="%d+"', 'cx="' .. new_cx .. '"')
                                    new_a_ext = new_a_ext:gsub('cy="%d+"', 'cy="' .. new_cy .. '"')
                                    content = content:sub(1, a_ext_start - 1) .. new_a_ext .. content:sub(a_ext_end + 2)
                                end
                            end

                            scaled_count = scaled_count + 1
                        end
                    end
                end
            end
        end

        if scaled_count > 0 then
            log.debug("[SECTION-MGR] Upscaled %d landscape images", scaled_count)
        end
    end

    -- Pass 3: Replace marker + minimal sectPr paragraph with full sectPr paragraph
    -- Pattern: marker comment followed by a paragraph containing a minimal sectPr
    local replace_count = 0
    content = content:gsub(
        '<!%-%- specdown:sectPr:(%w+) %-%->%s*<w:p>.-<w:sectPr>.-</w:sectPr>.-</w:p>',
        function(orientation)
            replace_count = replace_count + 1
            local full_sectpr = section_builder(orientation)
            return '<w:p><w:pPr>' .. full_sectpr .. '</w:pPr></w:p>'
        end
    )

    log.debug("[SECTION-MGR] Replaced %d section marker paragraphs", replace_count)

    return content
end

return M
