---DOCX Post-Processor for SpecCompiler.
---Template-specific OOXML post-processing for DOCX files.
---Pandoc's DOCX writer regenerates styles with its own defaults, so templates
---can provide post-processors to fix them.
---
---Post-processors are loaded from: models/{template}/ooxml/postprocess.lua
---
---When template="default", this module serves as both the framework orchestrator
---AND the template module (Lua's require cache returns the same M table, so hooks
---added to M are found when load_template_postprocessor loads "default").
---
---@module backend.postprocessors.docx
local M = {}

-- Load zip utilities (cross-platform, uses lua-zip)
local zip_utils = require("infra.format.zip_utils")
local xml = require("infra.format.xml")
local table_formatter = require("infra.format.docx.table_formatter")
local heading_numberer = require("infra.format.docx.heading_numberer")
local bibliography_formatter = require("infra.format.docx.bibliography_formatter")
local header_builder = require("infra.format.docx.header_builder")

-- ============================================================================
-- Template Post-Processor Loading
-- ============================================================================

---Load template-specific OOXML post-processor.
---Loads from models/{template}/ooxml/postprocess.lua
---@param template_name string Template name (e.g., "abnt", "ieee")
---@param log table Logger instance
---@return table|nil Post-processor module or nil if not found
function M.load_template_postprocessor(template_name, log)
    if not template_name or template_name == '' then
        log.debug('[DOCX-POST] No template name provided, skipping postprocessor')
        return nil
    end

    -- Try new location first: models/{template}/postprocessors/docx
    local module_name = string.format("models.%s.postprocessors.docx", template_name)
    log.debug('[DOCX-POST] Attempting to load: %s', module_name)

    local ok, module = pcall(require, module_name)
    if ok and module then
        log.info('[DOCX-POST] Loaded post-processor for template: %s', template_name)
        -- Log available hooks
        local hooks = {}
        for k, v in pairs(module) do
            if type(v) == 'function' then
                table.insert(hooks, k)
            end
        end
        log.debug('[DOCX-POST] Available hooks: %s', table.concat(hooks, ', '))
        return module
    end

    -- Not finding a postprocessor is normal - many templates don't need one
    log.debug('[DOCX-POST] No post-processor found for template: %s (tried: %s)', template_name, module_name)
    return nil
end

-- ============================================================================
-- DOCX File Manipulation
-- ============================================================================

---Get absolute path for a file.
---@param file_path string File path (possibly relative)
---@return string Absolute path
local function get_absolute_path(file_path)
    if file_path:match('^/') then
        return file_path
    end

    local cwd = zip_utils.cwd()
    if cwd then
        return cwd .. '/' .. file_path
    end

    return file_path
end

---Extract DOCX to temporary directory.
---Uses lua-zip for cross-platform support.
---@param docx_path string Absolute path to DOCX file
---@param log table Logger instance
---@return string|nil Temp directory path, or nil on failure
local function extract_docx(docx_path, log)
    local temp_dir = os.tmpname() .. '_docx'

    local ok, err = zip_utils.extract(docx_path, temp_dir)
    if not ok then
        log.warn('[DOCX-POST] Failed to extract DOCX: %s (%s)', docx_path, tostring(err))
        zip_utils.rmdir_r(temp_dir)
        return nil
    end

    return temp_dir
end

---Repack DOCX from temporary directory.
---Uses lua-zip for cross-platform support.
---@param temp_dir string Temporary directory with DOCX contents
---@param docx_path string Absolute path for output DOCX file
---@param log table Logger instance
---@return boolean Success status
local function repack_docx(temp_dir, docx_path, log)
    local ok, err = zip_utils.create(temp_dir, docx_path)

    -- Cleanup temp directory
    zip_utils.rmdir_r(temp_dir)

    if ok then
        return true
    else
        log.warn('[DOCX-POST] Failed to repack DOCX: %s (%s)', docx_path, tostring(err))
        return false
    end
end

---Read XML file content.
---@param xml_path string Path to XML file
---@return string|nil Content or nil if failed
local function read_xml(xml_path)
    local f = io.open(xml_path, 'r')
    if not f then
        return nil
    end
    local content = f:read('*all')
    f:close()
    return content
end

---Write XML file content.
---@param xml_path string Path to XML file
---@param content string Content to write
---@return boolean Success status
local function write_xml(xml_path, content)
    local f = io.open(xml_path, 'w')
    if not f then
        return false
    end
    f:write(content)
    f:close()
    return true
end

-- ============================================================================
-- Base Document Processing (runs for all templates)
-- ============================================================================

-- A4 dimensions and margins in EMUs (English Metric Units)
-- 1 cm = 360000 EMUs
-- A4 = 21cm x 29.7cm
-- ABNT margins: left 3cm, right 2cm → text width = 16cm
local MAX_TEXT_WIDTH_EMU = 5760000  -- 16cm in EMUs (A4 with ABNT margins)

---Constrain image extent to fit within text margins.
---Scales down width (and proportionally height) if image is too wide.
---@param drawing_xml string The drawing element XML
---@return string Modified drawing XML with constrained extent
local function constrain_extent_to_margins(drawing_xml)
    -- Extract current extent values - handle both attribute orderings
    -- Pattern 1: cx="..." cy="..."
    -- Pattern 2: cy="..." cx="..."
    local cx = drawing_xml:match('wp:extent[^>]*cx="(%d+)"')
    local cy = drawing_xml:match('wp:extent[^>]*cy="(%d+)"')

    if not cx then return drawing_xml end

    local width = tonumber(cx)
    local height = tonumber(cy) or 0

    -- If width exceeds max, scale down proportionally
    if width > MAX_TEXT_WIDTH_EMU then
        local scale = MAX_TEXT_WIDTH_EMU / width
        local new_width = math.floor(MAX_TEXT_WIDTH_EMU)
        local new_height = math.floor(height * scale)

        -- Replace wp:extent element completely (handles any attribute ordering)
        local modified = drawing_xml:gsub(
            '(<wp:extent)[^/]*/>',
            string.format('%%1 cx="%d" cy="%d"/>', new_width, new_height)
        )

        -- Also scale a:ext if present (for picture element inside)
        modified = modified:gsub(
            '(<a:ext)[^/]*/>',
            function(prefix)
                -- Only replace if this a:ext has similar dimensions (the image extent)
                return string.format('%s cx="%d" cy="%d"/>', prefix, new_width, new_height)
            end
        )

        return modified
    end

    return drawing_xml
end

---Convert inline image to anchored format.
---For academic documents, position specifiers control wrapping behavior:
---  h = here (anchored to paragraph, flows with text)
---  t = top (anchored to paragraph, Word will try to place near top of page)
---  b = bottom (anchored to paragraph, Word will try to place near bottom)
---All use margin-relative positioning to stay within text area.
---@param drawing_xml string The <w:drawing> element XML
---@param _position string Position specifier (h, t, b) - reserved for future use
---@return string Modified drawing XML with wp:anchor instead of wp:inline
local function convert_to_anchored(drawing_xml, _position)
    -- First, constrain the image to fit within margins
    local modified = constrain_extent_to_margins(drawing_xml)

    -- All positions use paragraph-relative vertical positioning
    -- Word will naturally flow the anchored image with content
    -- The position hint is informational - Word handles actual placement
    local v_relative = "paragraph"
    local v_position = '<wp:posOffset>0</wp:posOffset>'

    -- Add anchor attributes and positioning elements
    -- Key settings:
    --   relativeFrom="margin" for horizontal = stays within text margins
    --   relativeFrom="paragraph" for vertical = flows with text
    --   wrapTopAndBottom = text wraps above/below, not beside
    modified = modified:gsub('<wp:inline([^>]*)>', function(attrs)
        return string.format([[<wp:anchor distT="0" distB="0" distL="0" distR="0"
               simplePos="0" relativeHeight="1" behindDoc="0"
               locked="0" layoutInCell="1" allowOverlap="0"%s>
            <wp:simplePos x="0" y="0"/>
            <wp:positionH relativeFrom="margin">
                <wp:align>center</wp:align>
            </wp:positionH>
            <wp:positionV relativeFrom="%s">
                %s
            </wp:positionV>]], attrs, v_relative, v_position)
    end)

    -- Replace closing tag
    modified = modified:gsub('</wp:inline>', '</wp:anchor>')

    -- Add wrap element before docPr (if not already present)
    if not modified:match('<wp:wrap') then
        modified = modified:gsub('(<wp:docPr)', '<wp:wrapTopAndBottom/>%1')
    end

    return modified
end

---Process float position markers and convert inline images to anchored.
---@param content string document.xml content
---@param log table Logger instance
---@return string Modified content
local function process_positioned_floats(content, log)
    local modified = content

    -- Find all float-position markers and track regions
    -- Format: <!-- speccompiler:float-position-start:POSITION:TYPE -->
    local pattern_start = '<!%-%- speccompiler:float%-position%-start:([htbp]):([A-Z]+) %-%->'
    local pattern_end = '<!%-%- speccompiler:float%-position%-end %-%->'

    -- Track positions of markers for removal
    local regions = {}
    local pos = 1

    while true do
        local start_pos, end_pos, position, float_type = modified:find(pattern_start, pos)
        if not start_pos then break end

        -- Find matching end marker
        local end_start, end_end = modified:find(pattern_end, end_pos)
        if end_start then
            table.insert(regions, {
                start_marker_begin = start_pos,
                start_marker_end = end_pos,
                end_marker_begin = end_start,
                end_marker_end = end_end,
                position = position,
                float_type = float_type,
            })
        end

        pos = end_pos + 1
    end

    -- Process regions in reverse order to maintain positions
    for i = #regions, 1, -1 do
        local region = regions[i]

        if region.float_type ~= "MATH" then  -- MATH is inline-only
            -- Extract content between markers
            local region_content = modified:sub(region.start_marker_end + 1, region.end_marker_begin - 1)

            -- Convert any inline images to anchored
            local modified_region = region_content:gsub(
                '(<w:drawing>.-</w:drawing>)',
                function(drawing)
                    if drawing:match('<wp:inline') then
                        log.debug('[DOCX-POST] Converting inline image to anchored (position=%s)', region.position)
                        return convert_to_anchored(drawing, region.position)
                    end
                    return drawing
                end
            )

            -- Rebuild content: before + modified region + after
            -- Remove markers in the process
            modified = modified:sub(1, region.start_marker_begin - 1) ..
                       modified_region ..
                       modified:sub(region.end_marker_end + 1)
        else
            -- Just remove markers for MATH (keep content as-is)
            modified = modified:sub(1, region.start_marker_begin - 1) ..
                       modified:sub(region.start_marker_end + 1, region.end_marker_begin - 1) ..
                       modified:sub(region.end_marker_end + 1)
        end
    end

    return modified
end

---Add keepNext property to float captions to prevent orphans.
---@param content string document.xml content
---@param _log table Logger instance (unused, kept for future debugging)
---@return string Modified content
local function add_keep_next_to_captions(content, _log)
    -- Find Caption-styled paragraphs and add keepNext
    -- This prevents captions from being separated from their floats
    local modified = content

    -- Pattern: <w:pStyle w:val="Caption"/> without keepNext
    modified = modified:gsub(
        '(<w:pPr>.-<w:pStyle w:val="Caption"/>.-)(</w:pPr>)',
        function(before, after)
            if not before:match('<w:keepNext') then
                return before .. '<w:keepNext/>' .. after
            end
            return before .. after
        end
    )

    return modified
end

---Base document processing that runs for all templates.
---Handles common features like positioned floats and caption orphan prevention.
---@param content string document.xml content
---@param log table Logger instance
---@return string Modified content
local function base_process_document(content, log)
    local modified = content

    -- Process positioned floats (convert inline to anchored where marked)
    modified = process_positioned_floats(modified, log)

    -- Add keepNext to captions to prevent orphans
    modified = add_keep_next_to_captions(modified, log)

    return modified
end

-- ============================================================================
-- Main Post-Processing
-- ============================================================================

-- NOTE: Cross-document hyperlink bookmark navigation is a known LibreOffice limitation.
-- LibreOffice opens external DOCX files but doesn't navigate to bookmarks within them.
-- Pandoc's default format (Target="file.docx#bookmark") works for Microsoft Word.
-- See: https://ask.libreoffice.org/t/problems-with-expernal-hyperlinks-to-word-documents-doc-and-docx/59421

-- NOTE: Template post-processors should provide these functions:
--   process_document(content, config, log) -> modified_content
--   process_styles(content, log, config) -> modified_content (config has paragraphStyles)
--   process_numbering(content, log) -> modified_content (optional)
--   process_content_types(content, log) -> modified_content (optional)
--   process_rels(content, log) -> modified_content (optional)
--   create_additional_parts(temp_dir, log, config) -> void (optional, for headers/footers)
--     config.spec_metadata contains spec-level attributes (report_no, revision, etc.)

---Main DOCX post-processor - loads template-specific handlers.
---The template post-processor handles all template-specific logic.
---This function handles file extraction/repacking, generic fixes (hyperlinks),
---and calls template-specific hooks.
---
---@param docx_path string Path to DOCX file
---@param template_name string Template name (e.g., "abnt")
---@param log table Logger instance
---@param config table|nil Optional style configuration passed to template
---@return boolean Success status
function M.postprocess(docx_path, template_name, log, config)
    -- Load template-specific post-processor (may be nil)
    local pp = M.load_template_postprocessor(template_name, log)

    -- Get absolute path for the DOCX file
    local abs_docx_path = get_absolute_path(docx_path)

    -- Extract DOCX to temp directory
    local temp_dir = extract_docx(abs_docx_path, log)
    if not temp_dir then
        return false
    end

    log.debug('[DOCX-POST] Starting post-processing for: %s', abs_docx_path)

    -- ========================================================================
    -- TEMPLATE-SPECIFIC HOOKS
    -- ========================================================================

    -- Process document.xml.rels (optional)
    local rels_path = temp_dir .. '/word/_rels/document.xml.rels'
    local rels_content = read_xml(rels_path)
    if rels_content and pp and pp.process_rels then
        log.debug('[DOCX-POST] Calling hook: process_rels')
        rels_content = pp.process_rels(rels_content, log)
        write_xml(rels_path, rels_content)
    end

    -- Process document.xml
    local doc_xml_path = temp_dir .. '/word/document.xml'
    local doc_content = read_xml(doc_xml_path)
    if not doc_content then
        log.warn('[DOCX-POST] Could not open document.xml')
        zip_utils.rmdir_r(temp_dir)
        return false
    end

    -- Apply base document processing (runs for all templates)
    -- Handles: positioned floats, caption orphan prevention
    log.debug('[DOCX-POST] Running base document processing')
    doc_content = base_process_document(doc_content, log)

    -- Apply template-specific document processing
    if pp and pp.process_document then
        log.debug('[DOCX-POST] Calling hook: process_document')
        doc_content = pp.process_document(doc_content, config, log, rels_content)
    end

    -- Write modified document.xml
    write_xml(doc_xml_path, doc_content)

    -- Process styles.xml (optional)
    -- Pass config for style injection from config.lua
    local styles_xml_path = temp_dir .. '/word/styles.xml'
    local styles_content = read_xml(styles_xml_path)
    if styles_content and pp and pp.process_styles then
        log.debug('[DOCX-POST] Calling hook: process_styles')
        styles_content = pp.process_styles(styles_content, log, config)
        write_xml(styles_xml_path, styles_content)
    end

    -- Process numbering.xml (create skeleton if missing so heading numbering can be injected)
    local numbering_xml_path = temp_dir .. '/word/numbering.xml'
    local numbering_content = read_xml(numbering_xml_path)
    local numbering_created = false
    if not numbering_content and pp and pp.process_numbering then
        numbering_content = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
</w:numbering>]]
        numbering_created = true
        log.debug('[DOCX-POST] Created minimal numbering.xml skeleton')
    end
    if numbering_content and pp and pp.process_numbering then
        log.debug('[DOCX-POST] Calling hook: process_numbering')
        numbering_content = pp.process_numbering(numbering_content, log)
        write_xml(numbering_xml_path, numbering_content)

        -- Register numbering.xml in content types and relationships if newly created
        if numbering_created then
            local ct_path = temp_dir .. '/[Content_Types].xml'
            local ct_content = read_xml(ct_path)
            if ct_content and not ct_content:match('numbering%.xml') then
                ct_content = ct_content:gsub('</Types>',
                    '<Override PartName="/word/numbering.xml"'
                    .. ' ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
                    .. '</Types>')
                write_xml(ct_path, ct_content)
                log.debug('[DOCX-POST] Registered numbering.xml in [Content_Types].xml')
            end

            local rels_xml_path = temp_dir .. '/word/_rels/document.xml.rels'
            local rels_xml = read_xml(rels_xml_path)
            if rels_xml and not rels_xml:match('numbering%.xml') then
                rels_xml = rels_xml:gsub('</Relationships>',
                    '<Relationship Id="rIdNumbering"'
                    .. ' Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering"'
                    .. ' Target="numbering.xml"/>'
                    .. '</Relationships>')
                write_xml(rels_xml_path, rels_xml)
                log.debug('[DOCX-POST] Registered numbering.xml in document.xml.rels')
            end
        end
    end

    -- Process [Content_Types].xml (optional)
    local content_types_path = temp_dir .. '/[Content_Types].xml'
    local content_types = read_xml(content_types_path)
    if content_types and pp and pp.process_content_types then
        log.debug('[DOCX-POST] Calling hook: process_content_types')
        content_types = pp.process_content_types(content_types, log)
        write_xml(content_types_path, content_types)
    end

    -- Process settings.xml (optional - for evenAndOddHeaders, etc.)
    local settings_xml_path = temp_dir .. '/word/settings.xml'
    local settings_content = read_xml(settings_xml_path)
    if settings_content and pp and pp.process_settings then
        log.debug('[DOCX-POST] Calling hook: process_settings')
        settings_content = pp.process_settings(settings_content, log)
        write_xml(settings_xml_path, settings_content)
    end

    -- Create additional parts like headers/footers (optional)
    -- Pass config for spec metadata (report_no, revision, etc.)
    if pp and pp.create_additional_parts then
        log.debug('[DOCX-POST] Calling hook: create_additional_parts')
        pp.create_additional_parts(temp_dir, log, config)
    end

    -- Repack DOCX
    local success = repack_docx(temp_dir, abs_docx_path, log)
    if success then
        log.debug('[DOCX-POST] Post-processing complete for template %s: %s', template_name, abs_docx_path)
    end

    return success
end

---Extract reference.docx styles for use in DOCX generation.
---This is useful when you need to merge styles from a reference document.
---@param reference_doc string Path to reference DOCX
---@param log table Logger instance
---@return string|nil styles_xml
---@return string|nil numbering_xml
---@return string|nil settings_xml
function M.extract_reference_styles(reference_doc, log)
    local abs_path = get_absolute_path(reference_doc)

    -- Check if reference doc exists
    if not zip_utils.path_exists(abs_path) then
        log.warn('[DOCX-POST] Reference document not found: %s', abs_path)
        return nil, nil, nil
    end

    -- Extract to temp directory
    local temp_dir = extract_docx(abs_path, log)
    if not temp_dir then
        return nil, nil, nil
    end

    -- Read the XML files
    local styles_xml = read_xml(temp_dir .. '/word/styles.xml')
    local numbering_xml = read_xml(temp_dir .. '/word/numbering.xml')
    local settings_xml = read_xml(temp_dir .. '/word/settings.xml')

    -- Cleanup
    zip_utils.rmdir_r(temp_dir)

    return styles_xml, numbering_xml, settings_xml
end

-- ============================================================================
-- Default Template Hooks (Corporate Report Styling)
-- ============================================================================
-- When template="default", these hooks provide basic professional formatting:
-- tables with borders and header shading, heading numbering, page numbers,
-- bibliography styling, and code block formatting.

-- Default table formatting config: full borders, neutral gray header shading.
local DEFAULT_TABLE_CONFIG = {
    skip_count = 0,
    borders = { style = "single", sz = "6", space = "0", color = "000000" },
    cell_margins = { top = "57", bottom = "57", left = "108", right = "108" },
    paragraph = { zero_indent = true, compact_spacing = true },
    header = { shading = "E8E8E8", bold = true },
}

-- Default heading numbering: single multilevel definition (1, 1.1, 1.1.1, etc.)
-- Uses high IDs (100) to avoid conflicts with Pandoc's auto-generated list numbering.
local DEFAULT_NUMBERING_DEFINITIONS = {
    {
        abstract_num_id = "100",
        nsid = "A0B1C2D3",
        tmpl = "D3C2B1A0",
        name = "HeadingNumbering",
        multi_level_type = "multilevel",
        num_id = "100",
        levels = {
            { ilvl = "0", start = "1", num_fmt = "decimal", lvl_text = "%1", suffix = "space", pstyle = "Heading1" },
            { ilvl = "1", start = "1", num_fmt = "decimal", lvl_text = "%1.%2", suffix = "space", pstyle = "Heading2", restart_level = 0 },
            { ilvl = "2", start = "1", num_fmt = "decimal", lvl_text = "%1.%2.%3", suffix = "space", pstyle = "Heading3", restart_level = 1 },
            { ilvl = "3", start = "1", num_fmt = "decimal", lvl_text = "%1.%2.%3.%4", suffix = "space", pstyle = "Heading4", restart_level = 2 },
            { ilvl = "4", start = "1", num_fmt = "decimal", lvl_text = "%1.%2.%3.%4.%5", suffix = "space", pstyle = "Heading5", restart_level = 3 },
        },
    },
}

-- Default heading → numbering map.
local DEFAULT_HEADING_MAP = {
    Heading1 = { ilvl = "0", numId = "100" },
    Heading2 = { ilvl = "1", numId = "100" },
    Heading3 = { ilvl = "2", numId = "100" },
    Heading4 = { ilvl = "3", numId = "100" },
    Heading5 = { ilvl = "4", numId = "100" },
}

-- Default bibliography config.
local DEFAULT_BIB_CONFIG = {
    heading_text = "REFERENCES",
    heading_style = "Heading1",
    entry_style = "Reference",
    page_break_before = false,
    skip_styles = { "Heading", "Caption", "Source" },
}

-- Default header/footer part definitions.
local DEFAULT_PARTS = {
    { file = "header1.xml", type = "header", rid = "rId9100" },
    { file = "header2.xml", type = "header", rid = "rId9101" },
    { file = "footer1.xml", type = "footer", rid = "rId9200" },
}

-- Default section references (first page header, default header, default footer).
local DEFAULT_SECTION_REFS = {
    { type = "first", rid = "rId9100", element = "header" },
    { type = "default", rid = "rId9101", element = "header" },
    { type = "default", rid = "rId9200", element = "footer" },
}

---Center figures by adding w:jc val="center" to paragraphs containing drawings.
---@param content string document.xml content
---@param log table Logger instance
---@return string Modified content
local function fix_figures(content, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end

    local body = xml.find_child(doc.root, "w:body")
    if not body then return content end

    local count = 0
    for _, para in ipairs(xml.find_by_name(body, "w:p")) do
        -- Check if this paragraph contains a drawing
        local has_drawing = false
        for _, r in ipairs(xml.find_by_name(para, "w:r")) do
            if xml.find_child(r, "w:drawing") then
                has_drawing = true
                break
            end
        end

        if has_drawing then
            -- Get or create pPr
            local pPr = xml.find_child(para, "w:pPr")
            if not pPr then
                pPr = xml.node("w:pPr")
                xml.insert_child(para, pPr, 1)
            end

            -- Add centering if not already present
            local jc = xml.find_child(pPr, "w:jc")
            if not jc then
                xml.add_child(pPr, xml.node("w:jc", { ["w:val"] = "center" }))
                count = count + 1
            end
        end
    end

    if count > 0 then
        log.debug('[DEFAULT-FIGURES] Centered %d figure paragraph(s)', count)
    end
    return xml.serialize(doc)
end

---Remove duplicate custom styles from styles.xml.
---Pandoc can generate duplicate style definitions when merging reference.docx.
---@param content string styles.xml content
---@param log table Logger instance
---@return string Modified content
local function remove_duplicate_custom_styles(content, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end

    local styles_root = doc.root
    if styles_root.name ~= "w:styles" then
        styles_root = xml.find_child(doc.root, "w:styles") or doc.root
    end

    local seen = {}
    local to_remove = {}
    for _, kid in ipairs(styles_root.kids or {}) do
        if kid.name == "w:style" then
            local style_id = xml.get_attr(kid, "w:styleId")
            if style_id then
                if seen[style_id] then
                    to_remove[#to_remove + 1] = kid
                else
                    seen[style_id] = true
                end
            end
        end
    end

    for _, node in ipairs(to_remove) do
        xml.remove_child(styles_root, node)
    end

    if #to_remove > 0 then
        log.debug('[DEFAULT-STYLES] Removed %d duplicate style(s)', #to_remove)
    end
    return xml.serialize(doc)
end

---Inject VerbatimChar and SourceCode styles if missing from styles.xml.
---@param content string styles.xml content
---@param log table Logger instance
---@return string Modified content
local function fix_code_styles(content, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end

    local styles_root = doc.root
    if styles_root.name ~= "w:styles" then
        styles_root = xml.find_child(doc.root, "w:styles") or doc.root
    end

    -- Check which styles already exist
    local existing = {}
    for _, kid in ipairs(styles_root.kids or {}) do
        if kid.name == "w:style" then
            local sid = xml.get_attr(kid, "w:styleId")
            if sid then existing[sid] = true end
        end
    end

    local added = 0

    -- VerbatimChar (character style)
    if not existing["VerbatimChar"] then
        xml.add_child(styles_root, xml.node("w:style", {
            ["w:type"] = "character", ["w:customStyle"] = "1", ["w:styleId"] = "VerbatimChar",
        }, {
            xml.node("w:name", { ["w:val"] = "Verbatim Char" }),
            xml.node("w:rPr", {}, {
                xml.node("w:rFonts", { ["w:ascii"] = "Courier New", ["w:hAnsi"] = "Courier New", ["w:cs"] = "Courier New" }),
                xml.node("w:sz", { ["w:val"] = "20" }),
                xml.node("w:szCs", { ["w:val"] = "20" }),
            }),
        }))
        added = added + 1
    end

    -- SourceCode (paragraph style)
    if not existing["SourceCode"] then
        xml.add_child(styles_root, xml.node("w:style", {
            ["w:type"] = "paragraph", ["w:customStyle"] = "1", ["w:styleId"] = "SourceCode",
        }, {
            xml.node("w:name", { ["w:val"] = "Source Code" }),
            xml.node("w:basedOn", { ["w:val"] = "Normal" }),
            xml.node("w:pPr", {}, {
                xml.node("w:spacing", { ["w:before"] = "0", ["w:after"] = "0", ["w:line"] = "240", ["w:lineRule"] = "auto" }),
                xml.node("w:jc", { ["w:val"] = "left" }),
                xml.node("w:pBdr", {}, {
                    xml.node("w:top",    { ["w:val"] = "single", ["w:sz"] = "4", ["w:space"] = "1", ["w:color"] = "CCCCCC" }),
                    xml.node("w:bottom", { ["w:val"] = "single", ["w:sz"] = "4", ["w:space"] = "1", ["w:color"] = "CCCCCC" }),
                    xml.node("w:left",   { ["w:val"] = "single", ["w:sz"] = "4", ["w:space"] = "1", ["w:color"] = "CCCCCC" }),
                    xml.node("w:right",  { ["w:val"] = "single", ["w:sz"] = "4", ["w:space"] = "1", ["w:color"] = "CCCCCC" }),
                }),
                xml.node("w:shd", { ["w:val"] = "clear", ["w:color"] = "auto", ["w:fill"] = "F5F5F5" }),
            }),
            xml.node("w:rPr", {}, {
                xml.node("w:rFonts", { ["w:ascii"] = "Courier New", ["w:hAnsi"] = "Courier New", ["w:cs"] = "Courier New" }),
                xml.node("w:sz", { ["w:val"] = "20" }),
                xml.node("w:szCs", { ["w:val"] = "20" }),
            }),
        }))
        added = added + 1
    end

    if added > 0 then
        log.debug('[DEFAULT-STYLES] Injected %d code style(s)', added)
    end
    return xml.serialize(doc)
end

---Inject a Word-native TOC field into document.xml before the first heading.
---Creates a dynamic field (w:fldChar sequence) that Word/LibreOffice renders
---on document open, rather than Pandoc's static inline TOC.
---@param content string document.xml content
---@param log table Logger instance
---@return string Modified content
local function inject_toc_field(content, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end

    local body = xml.find_child(doc.root, "w:body")
    if not body then return content end

    -- Find the first heading paragraph
    local first_heading_idx = nil
    for i, kid in ipairs(body.kids or {}) do
        if kid.name == "w:p" or (kid.nsPrefix and kid.nsPrefix .. ":" .. kid.name == "w:p") then
            local pPr = xml.find_child(kid, "w:pPr")
            if pPr then
                local pStyle = xml.find_child(pPr, "w:pStyle")
                if pStyle then
                    local val = xml.get_attr(pStyle, "w:val")
                    if val and val:match("^Heading%d$") then
                        first_heading_idx = i
                        break
                    end
                end
            end
        end
    end

    if not first_heading_idx then
        log.debug("[DEFAULT-TOC] No heading paragraphs found, skipping TOC injection")
        return content
    end

    -- TOC heading paragraph
    local toc_heading = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", { ["w:val"] = "TOCHeading" }),
        }),
        xml.node("w:r", {}, {
            xml.node("w:t", {}, { xml.text("Table of Contents") }),
        }),
    })

    -- TOC field: begin + instrText + separate
    local toc_field_start = xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:fldChar", { ["w:fldCharType"] = "begin" }),
        }),
        xml.node("w:r", {}, {
            xml.node("w:instrText", { ["xml:space"] = "preserve" }, {
                xml.text(' TOC \\o "1-3" \\h '),
            }),
        }),
        xml.node("w:r", {}, {
            xml.node("w:fldChar", { ["w:fldCharType"] = "separate" }),
        }),
    })

    -- TOC field end
    local toc_field_end = xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:fldChar", { ["w:fldCharType"] = "end" }),
        }),
    })

    -- Page break after TOC
    local page_break = xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:br", { ["w:type"] = "page" }),
        }),
    })

    -- Insert before first heading (in reverse order so indices stay correct)
    xml.insert_child(body, page_break, first_heading_idx)
    xml.insert_child(body, toc_field_end, first_heading_idx)
    xml.insert_child(body, toc_field_start, first_heading_idx)
    xml.insert_child(body, toc_heading, first_heading_idx)

    log.debug("[DEFAULT-TOC] Injected TOC field before first heading")
    return xml.serialize(doc)
end

---Process document.xml for default template.
---@param content string document.xml content
---@param config table Configuration
---@param log table Logger instance
---@return string Modified content
function M.process_document(content, config, log)
    content = table_formatter.format_tables(content, DEFAULT_TABLE_CONFIG, log)
    content = fix_figures(content, log)
    content = heading_numberer.apply_numbering(content, DEFAULT_HEADING_MAP, log)
    -- TOC is now handled by the toc: view + DOCX filter (speccompiler-toc Div)
    content = bibliography_formatter.format_bibliography(content, DEFAULT_BIB_CONFIG, log)
    content = header_builder.inject_section_references(content, DEFAULT_SECTION_REFS, log)
    return content
end

---Merge missing styles from reference.docx into styles.xml.
---Pandoc only copies styles from reference.docx that it uses natively.
---Styles referenced by raw OOXML (e.g., cover page styles) are not copied.
---@param content string styles.xml content
---@param log table Logger instance
---@param config table|nil Configuration with output_dir
---@return string Modified content
local function merge_reference_styles(content, log, config)
    if not config or not config.output_dir then return content end

    local ref_path = config.output_dir .. "/reference.docx"
    local ref_styles = M.extract_reference_styles(ref_path, log)
    if not ref_styles then return content end

    local doc = xml.parse(content)
    if not doc or not doc.root then return content end
    local styles_root = doc.root
    if styles_root.name ~= "w:styles" then
        styles_root = xml.find_child(doc.root, "w:styles") or doc.root
    end

    -- Collect existing style IDs using xml.find_children for proper namespace handling
    local existing = {}
    for _, style_el in ipairs(xml.find_children(styles_root, "w:style")) do
        local sid = xml.get_attr(style_el, "w:styleId")
        if sid then existing[sid] = true end
    end

    -- Parse reference styles
    local ref_doc = xml.parse(ref_styles)
    if not ref_doc or not ref_doc.root then
        log.debug("[DEFAULT-STYLES] Failed to parse reference styles.xml")
        return content
    end
    local ref_root = ref_doc.root
    if ref_root.name ~= "w:styles" then
        ref_root = xml.find_child(ref_doc.root, "w:styles") or ref_doc.root
    end

    -- Copy missing styles from reference
    local added = 0
    for _, style_el in ipairs(xml.find_children(ref_root, "w:style")) do
        local sid = xml.get_attr(style_el, "w:styleId")
        if sid and not existing[sid] then
            xml.add_child(styles_root, style_el)
            existing[sid] = true
            added = added + 1
        end
    end

    if added > 0 then
        log.debug("[DEFAULT-STYLES] Merged %d style(s) from reference.docx", added)
    end
    return xml.serialize(doc)
end

---Fix heading styles in styles.xml.
---Pandoc regenerates heading styles with its own defaults (blue/teal color),
---overriding the preset values from reference.docx. This function forces
---black font color and adds pageBreakBefore to Heading1.
---@param content string styles.xml content
---@param log table Logger instance
---@return string Modified content
local function fix_heading_styles(content, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then return content end

    local styles_root = doc.root
    if styles_root.name ~= "w:styles" then
        styles_root = xml.find_child(doc.root, "w:styles") or doc.root
    end

    local heading_ids = { Heading1 = true, Heading2 = true, Heading3 = true,
                          Heading4 = true, Heading5 = true }
    local fixed = 0

    for _, style_el in ipairs(xml.find_children(styles_root, "w:style")) do
        local sid = xml.get_attr(style_el, "w:styleId")
        if sid and heading_ids[sid] then
            -- Force black font color in rPr
            local rPr = xml.find_child(style_el, "w:rPr")
            if not rPr then
                rPr = xml.node("w:rPr")
                xml.add_child(style_el, rPr)
            end
            local color = xml.find_child(rPr, "w:color")
            if color then
                xml.set_attr(color, "w:val", "000000")
            else
                xml.add_child(rPr, xml.node("w:color", { ["w:val"] = "000000" }))
            end
            fixed = fixed + 1

            -- Heading1: ensure pageBreakBefore
            if sid == "Heading1" then
                local pPr = xml.find_child(style_el, "w:pPr")
                if pPr and not xml.find_child(pPr, "w:pageBreakBefore") then
                    xml.add_child(pPr, xml.node("w:pageBreakBefore"))
                    log.debug("[DEFAULT-STYLES] Added pageBreakBefore to Heading1")
                end
            end
        end
    end

    if fixed > 0 then
        log.debug("[DEFAULT-STYLES] Fixed font color to black on %d heading style(s)", fixed)
    end
    return xml.serialize(doc)
end

---Process styles.xml for default template.
---@param content string styles.xml content
---@param log table Logger instance
---@param config table|nil Configuration with output_dir
---@return string Modified content
function M.process_styles(content, log, config)
    content = remove_duplicate_custom_styles(content, log)
    content = fix_code_styles(content, log)
    content = fix_heading_styles(content, log)
    content = merge_reference_styles(content, log, config)
    return content
end

---Process numbering.xml for default template.
---@param content string numbering.xml content
---@param log table Logger instance
---@return string Modified content
function M.process_numbering(content, log)
    return heading_numberer.merge_numbering(content, DEFAULT_NUMBERING_DEFINITIONS, log)
end

---Process [Content_Types].xml for default template.
---@param content string [Content_Types].xml content
---@param log table Logger instance
---@return string Modified content
function M.process_content_types(content, log)
    return header_builder.register_content_types(content, DEFAULT_PARTS, log)
end

---Process document.xml.rels for default template.
---@param content string document.xml.rels content
---@param log table Logger instance
---@return string Modified content
function M.process_rels(content, log)
    local result = header_builder.register_relationships(content, DEFAULT_PARTS, log)
    return result
end

---Build a corporate three-zone footer table.
---Layout: [left_text] [center_text] [Page N of M]
---@param left_text string Left zone text (e.g., document ID + version)
---@param center_text string Center zone text (e.g., classification)
---@return string Footer XML
local function build_corporate_footer(left_text, center_text)
    -- Build the right zone: "Page " + PAGE field + " of " + NUMPAGES field
    local right_children = {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = "Footer"}),
            xml.node("w:jc", {["w:val"] = "right"}),
        }),
        xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text("Page ")}),
        }),
    }
    for _, r in ipairs(header_builder.build_field_runs(" PAGE ")) do
        right_children[#right_children + 1] = r
    end
    right_children[#right_children + 1] = xml.node("w:r", {}, {
        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(" of ")}),
    })
    for _, r in ipairs(header_builder.build_field_runs(" NUMPAGES ")) do
        right_children[#right_children + 1] = r
    end

    -- A4 text width: 11906 - 2*1440 (1in margins) = 9026 twips
    -- Each of 3 columns = 9026/3 ≈ 3009 twips
    local col_width_twips = "3009"
    -- For tcW in pct mode: 5000 = 100%, so each cell = 5000/3 ≈ 1667
    local col_width_pct = "1667"

    -- Build the three-cell table row
    local footer_table = xml.node("w:tbl", {}, {
        -- Table properties: full width, no borders
        xml.node("w:tblPr", {}, {
            xml.node("w:tblW", {["w:w"] = "5000", ["w:type"] = "pct"}),
            xml.node("w:tblBorders", {}, {
                xml.node("w:top", {["w:val"] = "single", ["w:sz"] = "4", ["w:space"] = "1", ["w:color"] = "CCCCCC"}),
                xml.node("w:bottom", {["w:val"] = "none", ["w:sz"] = "0", ["w:space"] = "0", ["w:color"] = "auto"}),
                xml.node("w:left", {["w:val"] = "none", ["w:sz"] = "0", ["w:space"] = "0", ["w:color"] = "auto"}),
                xml.node("w:right", {["w:val"] = "none", ["w:sz"] = "0", ["w:space"] = "0", ["w:color"] = "auto"}),
                xml.node("w:insideH", {["w:val"] = "none", ["w:sz"] = "0", ["w:space"] = "0", ["w:color"] = "auto"}),
                xml.node("w:insideV", {["w:val"] = "none", ["w:sz"] = "0", ["w:space"] = "0", ["w:color"] = "auto"}),
            }),
            xml.node("w:tblLayout", {["w:type"] = "fixed"}),
        }),
        -- Grid definition (twips)
        xml.node("w:tblGrid", {}, {
            xml.node("w:gridCol", {["w:w"] = col_width_twips}),
            xml.node("w:gridCol", {["w:w"] = col_width_twips}),
            xml.node("w:gridCol", {["w:w"] = col_width_twips}),
        }),
        -- Single row with three cells
        xml.node("w:tr", {}, {
            -- Left cell: document ID / version
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = col_width_pct, ["w:type"] = "pct"}),
                }),
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:pStyle", {["w:val"] = "Footer"}),
                        xml.node("w:jc", {["w:val"] = "left"}),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(left_text or "")}),
                    }),
                }),
            }),
            -- Center cell: classification or empty
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = col_width_pct, ["w:type"] = "pct"}),
                }),
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:pStyle", {["w:val"] = "Footer"}),
                        xml.node("w:jc", {["w:val"] = "center"}),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(center_text or "")}),
                    }),
                }),
            }),
            -- Right cell: Page N of M
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = col_width_pct, ["w:type"] = "pct"}),
                }),
                xml.node("w:p", {}, right_children),
            }),
        }),
    })

    return header_builder.build_footer_xml(header_builder.HDR_NAMESPACES, {footer_table})
end

---Create additional parts (headers, footer) for default template.
---@param temp_dir string Path to extracted DOCX temp directory
---@param log table Logger instance
---@param config table|nil Configuration with optional spec_metadata
function M.create_additional_parts(temp_dir, log, config)
    -- header1.xml: Empty first page (no header on title page)
    local header1 = header_builder.build_empty_header()

    -- header2.xml: Default page with right-aligned page number
    local header2 = header_builder.build_page_number_header("right")

    -- footer1.xml: Corporate three-zone footer
    -- [doc_id | version]  [classification]  [Page N of M]
    local spec_meta = (config and config.spec_metadata) or {}
    local doc_id = spec_meta.document_id or ""
    local version_str = spec_meta.version or ""
    local classification = spec_meta.classification or ""

    -- Build left zone text
    local left_text = doc_id
    if version_str ~= "" then
        if left_text ~= "" then
            left_text = left_text .. "  |  v" .. version_str
        else
            left_text = "v" .. version_str
        end
    end

    local footer1 = build_corporate_footer(left_text, classification)

    header_builder.write_parts(temp_dir, {
        { file = "header1.xml", content = header1 },
        { file = "header2.xml", content = header2 },
        { file = "footer1.xml", content = footer1 },
    }, log)
end

-- ============================================================================
-- Writer Interface
-- ============================================================================

---Run the DOCX postprocessor.
---This is the standard interface called by the writer:
---  postprocessor.run(out_path, config, log)
---
---@param path string Path to the DOCX file
---@param config table Configuration (must contain template or docx settings)
---@param log table Logger instance
---@return boolean Success status
function M.run(path, config, log)
    local template = config.template or "default"
    local docx_config = config.docx or config
    return M.postprocess(path, template, log, docx_config)
end

---Query spec-level attributes from the SpecIR database.
---Returns a table of {name = value} for attributes without an object/float owner.
---@param db_path string Path to specir.db
---@param log table Logger instance
---@return table spec_metadata Key-value pairs of spec-level attributes
local function query_spec_metadata(db_path, log)
    local ok, sqlite = pcall(require, "lsqlite3")
    if not ok then
        log.debug("[DOCX-POST] lsqlite3 not available, skipping spec metadata query")
        return {}
    end

    local db = sqlite.open(db_path)
    if not db then
        log.debug("[DOCX-POST] Could not open database: %s", db_path)
        return {}
    end

    local meta = {}
    local sql = [[
        SELECT name, string_value, raw_value
        FROM spec_attribute_values
        WHERE owner_object_id IS NULL
          AND owner_float_id IS NULL
    ]]

    for row in db:nrows(sql) do
        local name = row.name and row.name:lower() or ""
        meta[name] = row.string_value or row.raw_value or ""
    end

    db:close()
    local count = 0
    for _ in pairs(meta) do count = count + 1 end
    log.debug("[DOCX-POST] Loaded spec metadata: %d attribute(s)", count)
    return meta
end

---Finalize DOCX postprocessing for all generated files.
---Called by the emitter after all DOCX files are generated.
---Queries spec-level metadata from the database and runs postprocessing
---on each file.
---@param paths string[] List of DOCX file paths
---@param config table Configuration with template, output_dir, db_path
---@param log table Logger instance
function M.finalize(paths, config, log)
    -- Query spec-level metadata from database for footer content
    local spec_metadata = {}
    if config.db_path then
        spec_metadata = query_spec_metadata(config.db_path, log)
    end

    -- Enrich config with spec metadata
    config.spec_metadata = spec_metadata

    for _, path in ipairs(paths) do
        local ok, err = pcall(M.run, path, config, log)
        if not ok then
            log.warn("[DOCX-POST] Postprocess failed for %s: %s", path, tostring(err))
        end
    end
end

return M
