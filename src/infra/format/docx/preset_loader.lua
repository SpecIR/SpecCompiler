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

return M
