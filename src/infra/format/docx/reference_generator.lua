---Reference DOCX Generator for SpecCompiler.
---Generates reference.docx by merging custom styles into Pandoc's default.
---@module reference_generator

local style_builder = require("infra.format.docx.style_builder")
local zip_utils = require("infra.format.zip_utils")

local M = {}

-- ============================================================================
-- DOCX Manipulation (via zip_utils)
-- ============================================================================

---Execute a shell command and return output.
---@param cmd string The command to execute
---@return string|nil output Command output, or nil on error
---@return string|nil error Error message if command failed
local function exec(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then
        return nil, "Failed to execute command: " .. cmd
    end

    local output = handle:read("*a")
    local ok = handle:close()

    if not ok then
        return nil, "Command failed: " .. cmd .. "\n" .. (output or "")
    end

    return output, nil
end

---Get Pandoc's default reference.docx as binary data.
---@return string|nil data Binary data of reference.docx
---@return string|nil error Error message if failed
function M.get_pandoc_default_reference()
    -- Create temp file for output
    local temp_file = os.tmpname() .. ".docx"

    local _, err = exec(string.format(
        'pandoc --print-default-data-file reference.docx > "%s"',
        temp_file
    ))

    if err then
        os.remove(temp_file)
        return nil, "Failed to get Pandoc default reference.docx: " .. err
    end

    local f = io.open(temp_file, "rb")
    if not f then
        os.remove(temp_file)
        return nil, "Failed to read Pandoc default reference.docx"
    end

    local data = f:read("*a")
    f:close()
    os.remove(temp_file)

    return data, nil
end

---Extract all files from a DOCX to a directory.
---@param docx_path string Path to the DOCX file
---@param output_dir string Path to extract to
---@return boolean success
---@return string|nil error Error message if failed
function M.extract_zip(docx_path, output_dir)
    return zip_utils.extract(docx_path, output_dir)
end

---Create a ZIP archive from a directory.
---@param source_dir string Path to the directory to zip
---@param output_path string Path for the output ZIP file
---@return boolean success
---@return string|nil error Error message if failed
function M.create_zip(source_dir, output_path)
    return zip_utils.create(source_dir, output_path)
end

-- ============================================================================
-- Styles.xml Manipulation
-- ============================================================================

---Merge custom styles into styles.xml content.
---Replaces existing styles with same ID, adds new ones.
---@param styles_xml string The original styles.xml content
---@param preset table The preset with paragraph_styles, character_styles, table_styles
---@return string merged_xml The merged styles.xml content
function M.merge_styles(styles_xml, preset)
    -- Build map of custom styles by ID
    local custom_styles = {}

    -- Paragraph styles
    if preset.paragraph_styles then
        for _, style in ipairs(preset.paragraph_styles) do
            custom_styles[style.id] = style_builder.build_style_xml(style)
        end
    end

    -- Character styles
    if preset.character_styles then
        for _, style in ipairs(preset.character_styles) do
            custom_styles[style.id] = style_builder.build_character_style_xml(style)
        end
    end

    -- Find existing style IDs
    local existing_ids = {}
    for style_id in styles_xml:gmatch('<w:style[^>]*w:styleId="([^"]+)"') do
        existing_ids[style_id] = true
    end

    local result = styles_xml

    -- Replace existing styles
    for style_id, style_xml in pairs(custom_styles) do
        if existing_ids[style_id] then
            -- Replace existing style - match the entire w:style element
            local pattern = '<w:style[^>]*w:styleId="' .. style_id .. '"[^>]*>.-</w:style>'
            result = result:gsub(pattern, function()
                return style_xml
            end)
        end
    end

    -- Add new styles (ones that don't exist in the original)
    local new_styles = {}
    for style_id, style_xml in pairs(custom_styles) do
        if not existing_ids[style_id] then
            table.insert(new_styles, style_xml)
        end
    end

    if #new_styles > 0 then
        -- Insert before </w:styles>
        result = result:gsub("</w:styles>", table.concat(new_styles) .. "</w:styles>")
    end

    return result
end

---Update the default proofing language in styles.xml docDefaults.
---Pandoc's default reference.docx has w:val="en-US" in docDefaults/rPrDefault,
---which causes spell check squiggles for non-English documents.
---This function updates it to match the document language.
---@param styles_xml string The original styles.xml content
---@param language string The language code (e.g., "pt-BR")
---@return string updated_xml The updated styles.xml content
function M.update_styles_language(styles_xml, language)
    -- Isolate the docDefaults section to avoid modifying per-style w:lang elements
    local before, doc_defaults, after = styles_xml:match("^(.-<w:docDefaults>)(.-)(</w:docDefaults>.*)$")
    if not doc_defaults then
        return styles_xml  -- No docDefaults found
    end

    -- Update w:val (primary language) in the lang element within docDefaults
    doc_defaults = doc_defaults:gsub(
        '(<w:lang[^/]*w:val=")[^"]*(")',
        '%1' .. language .. '%2'
    )

    -- before already ends with "<w:docDefaults>", after starts with "</w:docDefaults>"
    return before .. doc_defaults .. after
end

---Update settings.xml with document language.
---@param settings_xml string The original settings.xml content
---@param language string The language code (e.g., "pt-BR")
---@return string updated_xml The updated settings.xml content
function M.update_settings_language(settings_xml, language)
    local new_theme_font_lang = string.format('<w:themeFontLang w:val="%s"/>', language)

    -- Try to replace existing themeFontLang
    local replaced = settings_xml:gsub('<w:themeFontLang[^/]*/>', new_theme_font_lang)
    if replaced ~= settings_xml then
        return replaced
    end

    -- Add before </w:settings>
    return settings_xml:gsub('</w:settings>', new_theme_font_lang .. '</w:settings>')
end

---Update settings.xml with mirror margins for two-sided printing.
---@param settings_xml string The original settings.xml content
---@param mirror_margins boolean Whether to enable mirror margins
---@return string updated_xml The updated settings.xml content
function M.update_settings_mirror_margins(settings_xml, mirror_margins)
    if not mirror_margins then
        return settings_xml
    end

    -- Check if mirrorMargins already exists
    if settings_xml:match('<w:mirrorMargins') then
        return settings_xml
    end

    -- Add <w:mirrorMargins/> before </w:settings>
    return settings_xml:gsub('</w:settings>', '<w:mirrorMargins/></w:settings>')
end

---Update document.xml with A4 page size in sectPr.
---Pandoc's default reference.docx has empty sectPr which causes LibreOffice
---to use system defaults (US Letter) during PDF export.
---@param document_xml string The original document.xml content
---@param width number Page width in twips (default 11906 for A4)
---@param height number Page height in twips (default 16838 for A4)
---@return string updated_xml The updated document.xml content
function M.update_document_page_size(document_xml, width, height)
    width = width or 11906   -- A4 width in twips
    height = height or 16838 -- A4 height in twips

    local page_size_xml = string.format('<w:pgSz w:w="%d" w:h="%d"/>', width, height)

    -- Replace empty self-closing sectPr with one containing page size
    local modified = document_xml:gsub(
        '<w:sectPr%s*/>',
        '<w:sectPr>' .. page_size_xml .. '</w:sectPr>'
    )

    -- Also add page size to sectPr elements that don't have it
    -- Pattern: <w:sectPr> followed by </w:sectPr> without pgSz in between
    modified = modified:gsub(
        '(<w:sectPr>)(%s*)(</w:sectPr>)',
        '%1%2' .. page_size_xml .. '%2%3'
    )

    return modified
end

-- ============================================================================
-- Main Generator
-- ============================================================================

---Options for reference.docx generation.
---@class ReferenceGeneratorOptions
---@field preset table The style preset
---@field output_path string Path for the output reference.docx
---@field language string|nil Document language (e.g., "pt-BR")
---@field log function|nil Optional logging function

---Generate reference.docx by merging preset styles into Pandoc's default.
---@param options ReferenceGeneratorOptions
---@return boolean success
---@return string|nil error Error message if failed
function M.generate(options)
    local preset = options.preset
    local output_path = options.output_path
    local language = options.language or (preset.settings and preset.settings.language)
    local log = options.log or function() end

    log("  Getting Pandoc default reference.docx...")

    -- Get Pandoc's default reference.docx
    local default_docx, err = M.get_pandoc_default_reference()
    if not default_docx then
        return false, err
    end
    log(string.format("  Got default reference.docx (%d bytes)", #default_docx))

    -- Create temp directory for work
    local temp_dir = os.tmpname() .. "_ref"
    local ok, mkdir_err = zip_utils.mkdir_p(temp_dir)
    if not ok then
        return false, "Failed to create temp directory: " .. (mkdir_err or "")
    end

    -- Write default docx to temp file
    local temp_docx = temp_dir .. "/default.docx"
    local f = io.open(temp_docx, "wb")
    if not f then
        zip_utils.rmdir_r(temp_dir)
        return false, "Failed to create temp file"
    end
    f:write(default_docx)
    f:close()

    -- Extract the DOCX
    local extract_dir = temp_dir .. "/extracted"
    zip_utils.mkdir_p(extract_dir)

    local extract_ok, extract_err = M.extract_zip(temp_docx, extract_dir)
    if not extract_ok then
        zip_utils.rmdir_r(temp_dir)
        return false, "Failed to extract default reference.docx: " .. (extract_err or "")
    end

    -- Read and merge styles.xml
    local styles_path = extract_dir .. "/word/styles.xml"
    local styles_file = io.open(styles_path, "r")
    if not styles_file then
        zip_utils.rmdir_r(temp_dir)
        return false, "Failed to read styles.xml from default reference.docx"
    end
    local styles_xml = styles_file:read("*a")
    styles_file:close()

    log(string.format("  Extracted styles.xml (%d chars)", #styles_xml))

    -- Merge custom styles
    local merged_styles = M.merge_styles(styles_xml, preset)
    log("  Merged custom styles into styles.xml")

    -- Update default proofing language in docDefaults
    if language then
        merged_styles = M.update_styles_language(merged_styles, language)
        log(string.format("  Set docDefaults proofing language: %s", language))
    end

    -- Write merged styles.xml
    styles_file = io.open(styles_path, "w")
    if not styles_file then
        zip_utils.rmdir_r(temp_dir)
        return false, "Failed to write merged styles.xml"
    end
    styles_file:write(merged_styles)
    styles_file:close()

    -- Update settings.xml with language and mirror margins
    local two_sided = preset.two_sided
    if language or two_sided then
        local settings_path = extract_dir .. "/word/settings.xml"
        local settings_file = io.open(settings_path, "r")
        if settings_file then
            local settings_xml = settings_file:read("*a")
            settings_file:close()

            -- Apply language setting
            if language then
                settings_xml = M.update_settings_language(settings_xml, language)
                log(string.format("  Set document language: %s", language))
            end

            -- Apply mirror margins for two-sided printing
            if two_sided then
                settings_xml = M.update_settings_mirror_margins(settings_xml, true)
                log("  Enabled mirror margins for two-sided printing")
            end

            settings_file = io.open(settings_path, "w")
            if settings_file then
                settings_file:write(settings_xml)
                settings_file:close()
            end
        end
    end

    -- Create the output DOCX (need absolute path for zip)
    local abs_output_path
    if output_path:sub(1, 1) == "/" then
        abs_output_path = output_path
    else
        local cwd = zip_utils.cwd()
        abs_output_path = cwd .. "/" .. output_path
    end

    -- Remove existing output if present
    os.remove(abs_output_path)

    ok, err = M.create_zip(extract_dir, abs_output_path)
    if not ok then
        zip_utils.rmdir_r(temp_dir)
        return false, "Failed to create reference.docx: " .. (err or "")
    end

    -- Cleanup
    zip_utils.rmdir_r(temp_dir)

    log(string.format("  Wrote: %s", output_path))

    return true, nil
end

---Generate reference.docx from a preset file.
---Convenience function that loads the preset and generates the reference.
---@param speccompiler_home string The SPECCOMPILER_HOME directory
---@param template string The template name
---@param preset_name string The preset name
---@param output_path string Path for the output reference.docx
---@param log function|nil Optional logging function
---@return boolean success
---@return string|nil error Error message if failed
function M.generate_from_preset(speccompiler_home, template, preset_name, output_path, log)
    log = log or function() end

    local preset_loader = require("infra.format.docx.preset_loader")

    log(string.format("Loading preset: %s/%s", template, preset_name))

    local preset, err = preset_loader.load_with_extends(speccompiler_home, template, preset_name)
    if not preset then
        return false, err
    end

    local valid, validate_err = preset_loader.validate(preset)
    if not valid then
        return false, "Invalid preset: " .. validate_err
    end

    log(string.format("  Preset '%s' loaded with %d paragraph styles",
        preset.name,
        #(preset.paragraph_styles or {})
    ))

    return M.generate({
        preset = preset,
        output_path = output_path,
        log = log,
    })
end

return M
