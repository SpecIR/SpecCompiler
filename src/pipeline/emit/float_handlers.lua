---Float Handler Dispatch for SpecCompiler.
---Model-agnostic dispatch to float handlers registered in spec_float_types.
---
---@module float_handlers
local M = {}

-- Cache for float handlers queried from spec_float_types
local float_handlers_cache = nil

---Query and cache float handlers from spec_float_types.
---Uses on_render_CodeBlock from the float type's handler module.
---The core has NO knowledge of what handlers exist - it just dispatches.
---@param data DataManager
---@param model string Model name (e.g., "default")
---@return table handlers Map of type_ref to {float_module, identifier}
function M.get_float_handlers(data, model)
    if float_handlers_cache then
        return float_handlers_cache
    end

    float_handlers_cache = {}
    model = model or "default"

    -- Query all float types
    local float_types = data:query_all([[
        SELECT identifier, aliases
        FROM spec_float_types
    ]])

    for _, ft in ipairs(float_types or {}) do
        -- Try to load the float module to get on_render_CodeBlock handler
        local module_path = string.format("models.%s.types.floats.%s",
            model, ft.identifier:lower())
        local ok, float_module = pcall(require, module_path)

        if ok and float_module and float_module.handler and
           type(float_module.handler.on_render_CodeBlock) == "function" then
            -- Register primary identifier
            float_handlers_cache[ft.identifier:upper()] = {
                float_module = float_module,
                identifier = ft.identifier
            }

            -- Register aliases as additional type_refs
            if ft.aliases and ft.aliases ~= "" then
                for alias in ft.aliases:gmatch("[^,]+") do
                    alias = alias:match("^%s*(.-)%s*$")  -- Trim
                    if alias ~= "" then
                        float_handlers_cache[alias:upper()] = {
                            float_module = float_module,
                            identifier = ft.identifier
                        }
                    end
                end
            end
        end
    end

    return float_handlers_cache
end

---Get handler for a specific float type.
---@param data DataManager
---@param type_ref string Float type reference (e.g., "MATH", "TABLE")
---@param model string|nil Model name (defaults to "default")
---@return table|nil handler {float_module, identifier} or nil
function M.get_handler_for_type(data, type_ref, model)
    local handlers = M.get_float_handlers(data, model or "default")
    return handlers[type_ref:upper()]
end

---Clear the float handlers cache.
---Call this when model changes or on new pipeline run.
function M.clear_cache()
    float_handlers_cache = nil
end

return M
