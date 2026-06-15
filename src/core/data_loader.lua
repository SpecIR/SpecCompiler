---Data Loader for SpecCompiler.
---Loads view modules for chart data injection.
---
---Views are Lua files that generate data for charts and other consumers.
---A view can optionally query the database using the provided DataManager.
---
---Directory structure:
---  models/{model}/types/views/{view_name}.lua
---
---View API (descriptor literal):
---  return {
---    kind = "view",
---    schema = { id = "...", inline_prefix = "...", ... },
---    hooks = { generate = function(params, data, spec_id) ... end },
---  }
---
---Where:
---  params  - user parameters from code block attributes
---  data    - DataManager instance for SQL queries
---  spec_id - Specification identifier
---
---@module data_loader
local M = {}

---Load a view module using require.
---@param view_name string View name (without extension)
---@param model_name string Model name (e.g., "abnt", "default")
---@return table|nil module The view module
---@return string|nil error Error message
local function try_load_view_module(view_name, model_name)
    local module_path = "models." .. model_name .. ".types.views." .. view_name
    local ok, view_module = pcall(require, module_path)

    if ok and view_module and type(view_module.dataset) == "function" then
        return view_module, nil
    end

    return nil, "View module not found (or no dataset hook): " .. module_path
end

---Load a view and return data.
---@param view_name string View name (without extension)
---@param model_name string Model name (e.g., "abnt", "default")
---@param data DataManager Database instance
---@param params table|nil Parameters for the view
---@param spec_id string|nil Specification identifier
---@return table|nil dataset Dataset with source array
---@return string|nil error Error message
function M.load_view(view_name, model_name, data, params, spec_id)
    -- Prefer the host's `dataset` hook for registered view types (file name ==
    -- lower(schema.id), and the host index is already overlaid default->model).
    local host = require("contract.registry").current()
    -- Inherited lookup: a view may alias another (e.g. GAUSSIAN extends GAUSS)
    -- and inherit its dataset hook through the extends chain, like every other
    -- hook dispatch path.
    local dataset = host and host:get_hook_inherited("view", view_name:upper(), "dataset")

    -- Fall back to loose module loading for views the host does not index:
    -- subdirectory/test-fixture modules (e.g. test_fixtures.params_echo) that
    -- export a top-level `dataset(dctx)`.
    if not dataset then
        local view_module, err = try_load_view_module(view_name, model_name)
        if not view_module and model_name ~= "default" then
            view_module, err = try_load_view_module(view_name, "default")
        end
        if not view_module then
            return nil, err or ("View not found: " .. view_name)
        end
        dataset = view_module.dataset
    end

    -- Data hooks take a single frozen DATA ctx: subject carries the parsed params,
    -- the DB is dctx.data, the spec is dctx.spec_id. (No render ctx in this phase.)
    local hook_ctx = require("pipeline.shared.hook_ctx")
    local dctx = hook_ctx.build_data({ model = model_name }, data, nil,
        { params = params or {} }, "dataset", spec_id)
    local gen_ok, result = pcall(dataset, dctx)
    if not gen_ok then
        return nil, "View execution failed: " .. tostring(result)
    end

    return result
end

---Inject data into chart config based on view attribute.
---@param config table ECharts config object
---@param attrs table Attributes from code block (view, model, spec_id)
---@param data DataManager Database instance
---@param log table Logger
---@return table config Modified config with injected data
---@return string|nil error Error if data injection failed
function M.inject_chart_data(config, attrs, data, log)
    attrs = attrs or {}
    log = log or { debug = function() end, info = function() end, warn = function() end }

    local view = attrs.view
    local model = attrs.model or "default"
    local spec_id = attrs.spec_id or "default"

    log.debug("inject_chart_data: view=%s, model=%s, spec_id=%s", tostring(view), tostring(model), tostring(spec_id))

    if not view then
        log.debug("No view specified, skipping data injection")
        return config, nil
    end

    log.info("Loading view: %s from model: %s", view, model)

    -- Parse params from attrs
    local params = {}
    for k, v in pairs(attrs) do
        if k ~= "view" and k ~= "model" and k ~= "caption" and k ~= "spec_id" then
            params[k] = tonumber(v) or v
        end
    end
    -- Also parse comma-separated params if present
    if attrs.params then
        for k, v in attrs.params:gmatch("([%w_]+)=([^,]+)") do
            params[k] = tonumber(v) or v
        end
    end

    local result, err = M.load_view(view, model, data, params, spec_id)
    if err then
        log.warn("View load failed: %s", err)
        return config, err
    end

    -- Detect chart type from series
    local is_sankey = false
    if config.series then
        for _, s in ipairs(config.series) do
            if s.type == "sankey" then
                is_sankey = true
                break
            end
        end
    end

    -- For Sankey charts, inject data/links into series[1] instead of dataset
    if is_sankey and result.data and result.links then
        if config.series and config.series[1] then
            config.series[1].data = result.data
            config.series[1].links = result.links
        end
        -- Clear dataset to avoid conflicts
        config.dataset = nil
        log.info("Injected Sankey data from view: %s (%d nodes, %d links)", view, #result.data, #result.links)
    elseif result.source then
        -- Standard dataset injection
        config.dataset = config.dataset or {}
        config.dataset.source = result.source
        log.info("Injected data from view: %s", view)
    else
        log.warn("View returned unknown format (expected source or data/links)")
    end

    return config, nil
end

return M
