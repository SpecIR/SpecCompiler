---View Handler Dispatch for SpecCompiler.
---Model-agnostic dispatch to view handlers registered in spec_view_types.
---Handles CodeBlock views (e.g., ```toc```, ```traceability_matrix```).
---
---@module view_handlers
local M = {}

-- Cache for view handlers queried from spec_view_types (per model)
local view_handlers_cache = {}

---Query and cache view handlers from spec_view_types.
---Uses on_render_CodeBlock from the view type's handler module.
---The core has NO knowledge of what handlers exist - it just dispatches.
---@param data DataManager
---@param model string Model name (e.g., "default", "sw_docs")
---@return table handlers Map of type_ref to {view_module, identifier}
function M.get_view_handlers(data, model)
    model = model or "default"
    if view_handlers_cache[model] then
        return view_handlers_cache[model]
    end

    local handlers_for_model = {}

    -- Query all view types
    local view_types = data:query_all([[
        SELECT identifier, aliases
        FROM spec_view_types
    ]])

    for _, vt in ipairs(view_types or {}) do
        -- Try to load the view module to get on_render_CodeBlock handler
        local module_path = string.format("models.%s.types.views.%s",
            model, vt.identifier:lower())
        local ok, view_module = pcall(require, module_path)

        if ok and view_module and view_module.handler and
           type(view_module.handler.on_render_CodeBlock) == "function" then
            -- Register primary identifier
            handlers_for_model[vt.identifier:upper()] = {
                view_module = view_module,
                identifier = vt.identifier
            }

            -- Register aliases as additional type_refs
            if vt.aliases and vt.aliases ~= "" then
                for alias in vt.aliases:gmatch("[^,]+") do
                    alias = alias:match("^%s*(.-)%s*$")  -- Trim
                    if alias ~= "" then
                        handlers_for_model[alias:upper()] = {
                            view_module = view_module,
                            identifier = vt.identifier
                        }
                    end
                end
            end
        end
    end

    view_handlers_cache[model] = handlers_for_model
    return handlers_for_model
end

---Get handler for a specific view type.
---@param data DataManager
---@param type_ref string View type reference (e.g., "TOC", "TRACEABILITY_MATRIX")
---@param model string|nil Model name (defaults to "default")
---@return table|nil handler {view_module, identifier} or nil
function M.get_handler_for_type(data, type_ref, model)
    local handlers = M.get_view_handlers(data, model or "default")
    return handlers[type_ref:upper()]
end

---Clear the view handlers cache.
---Call this when model changes or on new pipeline run.
function M.clear_cache()
    view_handlers_cache = {}
end

return M
