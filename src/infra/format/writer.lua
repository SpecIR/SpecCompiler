---Writer utilities for SpecCompiler.
---Provides filter and postprocessor loading for template-specific output.
---
---Note: Document writing is now handled by emitter.lua via external pandoc CLI.
---This module only provides utility functions still needed by the pipeline.
---
---@module backend.writer
local M = {}

-- ============================================================================
-- Module Loading
-- ============================================================================

---Try to load a Lua module, returning nil if not found.
---@param module_path string Module path in dot notation
---@return table|nil module The loaded module or nil
local function try_require(module_path)
    local ok, result = pcall(require, module_path)
    if ok then
        return result
    end
    return nil
end

-- ============================================================================
-- Filter Composition
-- ============================================================================

---Compose two filters into a single filter that runs both sequentially.
---The base filter runs first, then the extension filter.
---@param base_filter table Filter module with apply(doc, config, log)
---@param extension_filter table Filter module with apply(doc, config, log)
---@return table composed_filter A filter module with apply() that runs both
local function compose_filters(base_filter, extension_filter)
    return {
        apply = function(doc, config, log)
            -- Run base filter first (handles speccompiler markers, etc.)
            local result = doc
            if base_filter and base_filter.apply then
                result = base_filter.apply(result, config, log) or result
            end
            -- Run extension filter (handles template-specific stuff)
            if extension_filter and extension_filter.apply then
                result = extension_filter.apply(result, config, log) or result
            end
            return result
        end,
        -- Mark as composed so downstream can detect
        _composed = true,
        _base = base_filter,
        _extension = extension_filter,
    }
end

-- ============================================================================
-- Filter Loading
-- ============================================================================

---Load format-specific filter for a template.
---Filters run BEFORE Pandoc to convert semantic elements to format-specific output.
---
---Resolution order:
---  1. models/{template}/filters/{format}.lua (template-specific)
---  2. models/default/filters/{format}.lua (fallback)
---
---If the template filter sets extends_default = true, the default filter is loaded
---first and composed: default runs first (speccompiler markers), then template additions.
---This lets template filters add Div/Span handlers without duplicating default logic.
---
---@param template string Template name (e.g., "abnt", "default")
---@param format string Output format (e.g., "docx", "html5")
---@return table|nil filter Filter module with apply(doc, config, log) function, or nil
function M.load_filter(template, format)
    -- Normalize format: filter files use short names (html, latex)
    -- while Pandoc uses specific format names (html5, tex)
    local filter_format = format
    if format == "html5" or format == "html" then filter_format = "html" end
    if format == "tex" then filter_format = "latex" end

    local default_filter = try_require(string.format("models.default.filters.%s", filter_format))

    if template and template ~= '' and template ~= 'default' then
        local template_filter = try_require(string.format("models.%s.filters.%s", template, filter_format))
        if template_filter then
            -- If template filter extends default, compose them
            if template_filter.extends_default and default_filter then
                return compose_filters(default_filter, template_filter)
            end
            -- Otherwise template filter replaces default entirely
            return template_filter
        end
    end

    -- Fallback to default
    return default_filter
end

-- ============================================================================
-- Postprocessor Loading
-- ============================================================================

---Load format-specific postprocessor for a template.
---Tries models/{template}/postprocessors/{format}.lua first,
---then falls back to models/default/postprocessors/{format}.lua.
---@param template string Template name (e.g., "abnt", "default")
---@param format string Output format (e.g., "docx", "html5")
---@return table|nil postprocessor Postprocessor module with run(path, config, log) function, or nil
function M.load_postprocessor(template, format)
    if template and template ~= '' then
        local mod = try_require(string.format("models.%s.postprocessors.%s", template, format))
        if mod then
            return mod
        end
    end
    -- Fallback to default
    return try_require(string.format("models.default.postprocessors.%s", format))
end

return M
