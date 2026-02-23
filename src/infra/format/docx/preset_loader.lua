---Preset Loader for SpecCompiler DOCX Generation.
---Loads Lua preset files that define DOCX styles.
---@module preset_loader

local M = {}

-- ============================================================================
-- Preset Loading
-- ============================================================================

---Load a preset from a file path.
---@param path string Absolute path to the preset.lua file
---@return table|nil preset The loaded preset table, or nil on error
---@return string|nil error Error message if loading failed
function M.load_from_file(path)
    local chunk, load_err = loadfile(path)
    if not chunk then
        return nil, "Failed to load preset file: " .. (load_err or path)
    end

    local ok, preset = pcall(chunk)
    if not ok then
        return nil, "Failed to execute preset file: " .. (preset or "unknown error")
    end

    if type(preset) ~= "table" then
        return nil, "Preset file must return a table: " .. path
    end

    return preset, nil
end

---Resolve the path to a DOCX preset file.
---Searches in: models/<template>/styles/<preset>/preset.lua
---@param speccompiler_home string The SPECCOMPILER_HOME directory
---@param template string The template name (e.g., "abnt", "default")
---@param preset string The preset name (e.g., "academico", "default")
---@return string|nil path The resolved path, or nil if not found
function M.resolve_path(speccompiler_home, template, preset)
    local path = string.format(
        "%s/models/%s/styles/%s/preset.lua",
        speccompiler_home,
        template,
        preset
    )

    local f = io.open(path, "r")
    if f then
        f:close()
        return path
    end

    return nil
end

---Load a preset by template and preset name.
---@param speccompiler_home string The SPECCOMPILER_HOME directory
---@param template string The template name
---@param preset string The preset name
---@return table|nil preset The loaded preset table
---@return string|nil error Error message if loading failed
function M.load(speccompiler_home, template, preset)
    local path = M.resolve_path(speccompiler_home, template, preset)
    if not path then
        return nil, string.format(
            "Preset not found: %s/%s (looked in %s/models/%s/styles/%s/preset.lua)",
            template, preset, speccompiler_home, template, preset
        )
    end

    return M.load_from_file(path)
end

-- ============================================================================
-- Format-Specific Style Loading
-- ============================================================================

---Load format-specific styles (docx.lua or html.lua).
---@param speccompiler_home string The SPECCOMPILER_HOME directory
---@param template string The template name
---@param preset string The preset name
---@param format string The output format ("docx" or "html5")
---@return table|nil format_styles The format-specific styles, or nil if not found
---@return string|nil error Error message if loading failed
function M.load_format_styles(speccompiler_home, template, preset, format)
    -- Normalize format name
    local format_name = format
    if format == "html5" then
        format_name = "html"
    end

    local path = string.format(
        "%s/models/%s/styles/%s/%s.lua",
        speccompiler_home,
        template,
        preset,
        format_name
    )

    local f = io.open(path, "r")
    if not f then
        -- Not an error - format-specific styles are optional
        return nil, nil
    end
    f:close()

    return M.load_from_file(path)
end

---Get float style configuration for a specific float type and format.
---Merges preset caption config with format-specific overrides.
---@param preset table|nil The preset table
---@param format_styles table|nil Format-specific styles
---@param float_type string The float type (e.g., "FIGURE", "TABLE")
---@return table style The merged style configuration
function M.get_float_style(preset, format_styles, float_type)
    local style = {}

    -- Start with preset caption config if available
    local lower_type = float_type:lower()
    if preset and preset.captions and preset.captions[lower_type] then
        for k, v in pairs(preset.captions[lower_type]) do
            style[k] = v
        end
    end

    -- Override with format-specific styles
    if format_styles and format_styles.float_styles and format_styles.float_styles[float_type] then
        for k, v in pairs(format_styles.float_styles[float_type]) do
            style[k] = v
        end
    end

    return style
end

---Get object style configuration for a specific object type and format.
---@param format_styles table|nil Format-specific styles
---@param object_type string The object type (e.g., "SECTION", "HLR")
---@return table|nil style The style configuration, or nil if not found
function M.get_object_style(format_styles, object_type)
    if format_styles and format_styles.object_styles and format_styles.object_styles[object_type] then
        return format_styles.object_styles[object_type]
    end
    return nil
end

---Deep merge two tables (right table wins for conflicts).
---@param base table Base table
---@param override table Override table
---@return table merged New merged table
function M.deep_merge(base, override)
    local result = {}

    -- Copy base
    for k, v in pairs(base) do
        if type(v) == "table" then
            result[k] = M.deep_merge({}, v)
        else
            result[k] = v
        end
    end

    -- Merge override
    for k, v in pairs(override) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = M.deep_merge(result[k], v)
        else
            result[k] = v
        end
    end

    return result
end

---Merge multiple presets with later ones taking precedence.
---@param presets table[] Array of preset tables
---@return table merged The merged preset
function M.merge(presets)
    local result = {}

    for _, preset in ipairs(presets) do
        result = M.deep_merge(result, preset)
    end

    return result
end

---Load and merge a preset chain.
---If a preset has an "extends" field, load and merge the base preset first.
---@param speccompiler_home string The SPECCOMPILER_HOME directory
---@param template string The template name
---@param preset string The preset name
---@param visited table|nil Visited presets to detect cycles
---@return table|nil preset The merged preset table
---@return string|nil error Error message if loading failed
function M.load_with_extends(speccompiler_home, template, preset, visited)
    visited = visited or {}
    local key = template .. "/" .. preset

    -- Detect cycles
    if visited[key] then
        return nil, "Circular preset dependency detected: " .. key
    end
    visited[key] = true

    local preset_tbl, err = M.load(speccompiler_home, template, preset)
    if not preset_tbl then
        return nil, err
    end

    -- Check if this preset extends another
    if preset_tbl.extends then
        local extends = preset_tbl.extends
        local base_template = extends.template or template
        local base_preset = extends.preset

        local base_tbl, base_err = M.load_with_extends(
            speccompiler_home, base_template, base_preset, visited
        )
        if not base_tbl then
            return nil, "Failed to load base preset: " .. base_err
        end

        -- Merge base with this preset (this preset wins)
        preset_tbl = M.deep_merge(base_tbl, preset_tbl)
    end

    return preset_tbl, nil
end

-- ============================================================================
-- Preset Validation
-- ============================================================================

---Validate a preset has required fields.
---@param preset table The preset to validate
---@return boolean valid True if valid
---@return string|nil error Error message if invalid
function M.validate(preset)
    if not preset.name then
        return false, "Preset must have a 'name' field"
    end

    if not preset.page then
        return false, "Preset must have a 'page' configuration"
    end

    if not preset.paragraph_styles or #preset.paragraph_styles == 0 then
        return false, "Preset must have at least one paragraph style"
    end

    -- Validate each paragraph style has required fields
    for i, style in ipairs(preset.paragraph_styles) do
        if not style.id then
            return false, string.format("Paragraph style %d must have an 'id' field", i)
        end
        if not style.name then
            return false, string.format("Paragraph style '%s' must have a 'name' field", style.id)
        end
    end

    return true, nil
end

-- ============================================================================
-- Preset Query Functions
-- ============================================================================

---Get a paragraph style by ID from a preset.
---@param preset table The preset
---@param style_id string The style ID
---@return table|nil style The style definition, or nil if not found
function M.get_paragraph_style(preset, style_id)
    if not preset.paragraph_styles then
        return nil
    end

    for _, style in ipairs(preset.paragraph_styles) do
        if style.id == style_id then
            return style
        end
    end

    return nil
end

---Get a table style by ID from a preset.
---@param preset table The preset
---@param style_id string The style ID
---@return table|nil style The style definition, or nil if not found
function M.get_table_style(preset, style_id)
    if not preset.table_styles then
        return nil
    end

    for _, style in ipairs(preset.table_styles) do
        if style.id == style_id then
            return style
        end
    end

    return nil
end

---Get a character style by ID from a preset.
---@param preset table The preset
---@param style_id string The style ID
---@return table|nil style The style definition, or nil if not found
function M.get_character_style(preset, style_id)
    if not preset.character_styles then
        return nil
    end

    for _, style in ipairs(preset.character_styles) do
        if style.id == style_id then
            return style
        end
    end

    return nil
end

---Get caption configuration for a float type.
---@param preset table The preset
---@param float_type string The float type ("figure", "table", "listing", etc.)
---@return table|nil caption The caption configuration
function M.get_caption_config(preset, float_type)
    if preset.enhanced_captions and preset.enhanced_captions[float_type] then
        return preset.enhanced_captions[float_type]
    end

    if preset.captions then
        return preset.captions[float_type]
    end

    return nil
end

return M
