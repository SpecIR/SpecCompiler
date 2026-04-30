---Verification View Loader for SpecCompiler.
---Responsible for discovering, loading, and registering verification view modules from models.
---
---Verification view modules live in models/{model}/verification_views/ and export M.verification_view with:
---  view, policy_key, sql, message(row)
---
---Mirrors the type_loader.lua pattern for model-based extensibility.
---
---@module verification_view_loader

local M = {}

local uv = require("luv")

-- In-memory registry of loaded verification views
local verification_view_registry = {}   -- ordered array of verification view definitions
local verification_view_by_key = {}     -- policy_key -> verification view definition (for dedup/override)

-- Filesystem functions using luv (same pattern as type_loader.lua)
local function create_fs_adapter(uv_lib)
    local adapter = {}

    adapter.cwd = function() return uv_lib.cwd() end
    adapter.stat = function(path) return uv_lib.fs_stat(path) end
    adapter.scandir = function(path)
        local req, err = uv_lib.fs_scandir(path)
        if not req then return nil, err end
        local entries = {}
        while true do
            local name, entry_type = uv_lib.fs_scandir_next(req)
            if not name then break end
            table.insert(entries, { name = name, type = entry_type })
        end
        return entries
    end

    return adapter
end

local fs = create_fs_adapter(uv)

---Resolve filesystem path for a model's verification_views directory.
---@param model_name string Model name (e.g., "default")
---@return string|nil path Absolute path to verification_views directory, or nil if not found
local function resolve_verification_views_path(model_name)
    local speccompiler_home = os.getenv("SPECCOMPILER_HOME")
    if speccompiler_home then
        local verification_views_path = speccompiler_home .. "/models/" .. model_name .. "/verification_views"
        local stat = fs.stat(verification_views_path)
        if stat and stat.type == "directory" then
            return verification_views_path
        end
    end

    local cwd = fs.cwd()
    local verification_views_path = cwd .. "/models/" .. model_name .. "/verification_views"
    local stat = fs.stat(verification_views_path)
    if stat and stat.type == "directory" then
        return verification_views_path
    end
    return nil  -- No verification_views directory (not an error)
end

---Discover verification view modules in a model's verification_views directory.
---@param verification_views_path string Absolute path to verification_views directory
---@return table discovered Array of module names (without .lua extension)
local function discover_verification_views(verification_views_path)
    local discovered = {}
    local entries, err = fs.scandir(verification_views_path)
    if not entries then return discovered end

    for _, entry in ipairs(entries) do
        if entry.type == "file" and entry.name:match("%.lua$") then
            local name = entry.name:gsub("%.lua$", "")
            table.insert(discovered, name)
        end
    end
    table.sort(discovered)  -- Deterministic load order
    return discovered
end

---Register a single verification view definition.
---Later loads override earlier loads (model layering).
---@param verification_view table Verification view definition from module.verification_view
function M.register_verification_view(verification_view)
    if verification_view.disabled then
        -- Remove existing verification_view with this key (model suppression)
        if verification_view_by_key[verification_view.policy_key] then
            for i, existing in ipairs(verification_view_registry) do
                if existing.policy_key == verification_view.policy_key then
                    table.remove(verification_view_registry, i)
                    break
                end
            end
            verification_view_by_key[verification_view.policy_key] = nil
        end
        return
    end

    if verification_view_by_key[verification_view.policy_key] then
        -- Override: replace existing verification_view (model layering)
        for i, existing in ipairs(verification_view_registry) do
            if existing.policy_key == verification_view.policy_key then
                verification_view_registry[i] = verification_view
                break
            end
        end
    else
        table.insert(verification_view_registry, verification_view)
    end
    verification_view_by_key[verification_view.policy_key] = verification_view
end

---Create all verification view SQL views in the database.
---@param data DataManager
function M.create_views(data)
    for _, verification_view in ipairs(verification_view_registry) do
        if verification_view.sql then
            data.db:exec_sql(verification_view.sql)
        end
    end
end

---Load verification view modules from a model and register them.
---@param model_name string Name of the model (e.g., "default")
function M.load_model(model_name)
    local verification_views_path = resolve_verification_views_path(model_name)
    if not verification_views_path then
        return  -- No verification_views directory; model has no verification views
    end

    local modules = discover_verification_views(verification_views_path)
    local base_require = "models." .. model_name .. ".verification_views"

    for _, mod_name in ipairs(modules) do
        local full_path = base_require .. "." .. mod_name
        local ok, module = pcall(require, full_path)
        if ok then
            if module.verification_view then
                M.register_verification_view(module.verification_view)
            end
        else
            error("Failed to load verification view module: " .. full_path .. ": " .. tostring(module))
        end
    end
end

---Get all registered verification views (for verify_handler iteration).
---@return table[] Array of verification view definitions
function M.get_verification_views()
    return verification_view_registry
end

---Reset the registry (for testing).
function M.reset()
    verification_view_registry = {}
    verification_view_by_key = {}
end

return M
