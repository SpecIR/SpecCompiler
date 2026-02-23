---LaTeX Post-Processor for SpecCompiler.
---Template-specific LaTeX post-processing for .tex files.
---Pandoc generates standard LaTeX; templates can provide post-processors
---to transform it to their specific document class/style.
---
---Post-processors are loaded from: models/{template}/postprocessors/latex.lua
---
---@module backend.postprocessors.latex
local M = {}

-- ============================================================================
-- Template Post-Processor Loading
-- ============================================================================

---Load template-specific LaTeX post-processor.
---Loads from models/{template}/postprocessors/latex.lua
---@param template_name string Template name (e.g., "abnt", "ieee")
---@param log table Logger instance
---@return table|nil Post-processor module or nil if not found
function M.load_template_postprocessor(template_name, log)
    if not template_name or template_name == '' then
        log.debug('[LATEX-POST] No template name provided, skipping postprocessor')
        return nil
    end

    local module_name = string.format("models.%s.postprocessors.latex", template_name)
    log.debug('[LATEX-POST] Attempting to load: %s', module_name)

    local ok, module = pcall(require, module_name)
    if ok and module then
        log.info('[LATEX-POST] Loaded post-processor for template: %s', template_name)
        return module
    end

    -- Not finding a postprocessor is normal - many templates don't need one
    log.debug('[LATEX-POST] No post-processor found for template: %s (tried: %s)', template_name, module_name)
    return nil
end

-- ============================================================================
-- File Utilities
-- ============================================================================

---Read file content.
---@param path string Path to file
---@return string|nil Content or nil if failed
local function read_file(path)
    local f = io.open(path, 'r')
    if not f then
        return nil
    end
    local content = f:read('*all')
    f:close()
    return content
end

---Write file content.
---@param path string Path to file
---@param content string Content to write
---@return boolean Success status
local function write_file(path, content)
    local f = io.open(path, 'w')
    if not f then
        return false
    end
    f:write(content)
    f:close()
    return true
end

-- ============================================================================
-- Main Post-Processing
-- ============================================================================

---Main LaTeX post-processor entry point.
---Loads template-specific handlers and applies transformations.
---
---@param latex_path string Path to LaTeX file
---@param template_name string Template name (e.g., "abnt")
---@param log table Logger instance
---@param config table|nil Optional configuration passed to template
---@return boolean Success status
function M.postprocess(latex_path, template_name, log, config)
    -- Load template-specific post-processor (may be nil)
    local pp = M.load_template_postprocessor(template_name, log)

    -- Read LaTeX content
    local content = read_file(latex_path)
    if not content then
        log.warn('[LATEX-POST] Could not read LaTeX file: %s', latex_path)
        return false
    end

    log.debug('[LATEX-POST] Starting post-processing for: %s', latex_path)

    -- Apply template-specific transformations
    if pp and pp.process then
        log.debug('[LATEX-POST] Calling template process hook')
        content = pp.process(content, config, log)
    end

    -- Write modified content
    local success = write_file(latex_path, content)
    if success then
        log.debug('[LATEX-POST] Post-processing complete for template %s: %s', template_name, latex_path)
    else
        log.warn('[LATEX-POST] Failed to write modified LaTeX: %s', latex_path)
    end

    return success
end

-- ============================================================================
-- Writer Interface
-- ============================================================================

---Run the LaTeX postprocessor.
---This is the standard interface called by the writer:
---  postprocessor.run(out_path, config, log)
---
---@param path string Path to the LaTeX file
---@param config table Configuration (must contain template)
---@param log table Logger instance
---@return boolean Success status
function M.run(path, config, log)
    local template = config.template or "default"
    local latex_config = config.latex or config
    return M.postprocess(path, template, log, latex_config)
end

---Finalize batch of LaTeX files.
---This is called by the emitter after all Pandoc processes complete.
---@param paths table Array of LaTeX file paths
---@param config table Configuration (must contain template)
---@param log table Logger instance
function M.finalize(paths, config, log)
    for _, path in ipairs(paths) do
        local ok, err = pcall(M.run, path, config, log)
        if not ok then
            log.warn("[LATEX-POST] Postprocess failed for %s: %s", path, tostring(err))
        end
    end
end

return M
