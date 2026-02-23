---Inline View Handler Dispatch for SpecCompiler.
---Model-agnostic dispatch to view handlers registered in spec_view_types.
---
---@module inline_handlers
local M = {}

-- Cache for inline view handlers queried from spec_view_types (per model)
local inline_handlers_cache = {}

---Query and cache inline view handlers from spec_view_types.
---Uses on_render_Code from the view type's handler module.
---The core has NO knowledge of what handlers exist - it just dispatches.
---@param data DataManager
---@param model string Model name (e.g., "default")
---@return table handlers Array of {prefix, view_module, identifier}
function M.get_inline_handlers(data, model)
    model = model or "default"
    if inline_handlers_cache[model] then
        return inline_handlers_cache[model]
    end

    local handlers_for_model = {}

    -- Query view types that have inline handling defined
    -- inline_prefix: the syntax prefix (e.g., "abbrev", "math", "select")
    -- aliases: comma-separated list of additional prefixes
    local view_types = data:query_all([[
        SELECT identifier, inline_prefix, aliases
        FROM spec_view_types
        WHERE inline_prefix IS NOT NULL
    ]])

    for _, vt in ipairs(view_types or {}) do
        if vt.inline_prefix and vt.inline_prefix ~= "" then
            -- Try to load the view module to get on_render_Code handler
            -- Fall back to default model if not found in current model
            local module_path = string.format("models.%s.types.views.%s",
                model, vt.identifier:lower())
            local ok, view_module = pcall(require, module_path)
            if not ok and model ~= "default" then
                module_path = string.format("models.default.types.views.%s",
                    vt.identifier:lower())
                ok, view_module = pcall(require, module_path)
            end

            if ok and view_module then
                -- Check for on_render_Code handler or M.generate fallback
                local has_handler = view_module.handler and
                    type(view_module.handler.on_render_Code) == "function"
                local has_generate = type(view_module.generate) == "function"

                if has_handler or has_generate then
                    -- Register primary prefix
                    table.insert(handlers_for_model, {
                        prefix = vt.inline_prefix:lower(),
                        view_module = view_module,
                        identifier = vt.identifier,
                        use_generate = not has_handler and has_generate
                    })

                    -- Register aliases as additional prefixes
                    if vt.aliases and vt.aliases ~= "" then
                        for alias in vt.aliases:gmatch("[^,]+") do
                            alias = alias:match("^%s*(.-)%s*$")  -- Trim
                            if alias ~= "" then
                                table.insert(handlers_for_model, {
                                    prefix = alias:lower(),
                                    view_module = view_module,
                                    identifier = vt.identifier,
                                    use_generate = not has_handler and has_generate
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    inline_handlers_cache[model] = handlers_for_model
    return handlers_for_model
end

---Clear the inline handlers cache.
---Call this when model changes or on new pipeline run.
function M.clear_cache()
    inline_handlers_cache = {}
end

return M
