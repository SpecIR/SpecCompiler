---Proof Loader for SpecCompiler.
---Responsible for discovering, loading, and registering proof view modules from models.
---
---Proof modules live in models/{model}/proofs/ and export M.proof with:
---  view, policy_key, sql, message(row)
---
---Mirrors the type_loader.lua pattern for model-based extensibility.
---
---@module proof_loader

local M = {}

local uv = require("luv")

-- In-memory registry of loaded proofs
local proof_registry = {}   -- ordered array of proof definitions
local proof_by_key = {}     -- policy_key -> proof definition (for dedup/override)

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

---Resolve filesystem path for a model's proofs directory.
---@param model_name string Model name (e.g., "default")
---@return string|nil path Absolute path to proofs directory, or nil if not found
local function resolve_proofs_path(model_name)
    local speccompiler_home = os.getenv("SPECCOMPILER_HOME")
    if speccompiler_home then
        local proofs_path = speccompiler_home .. "/models/" .. model_name .. "/proofs"
        local stat = fs.stat(proofs_path)
        if stat and stat.type == "directory" then
            return proofs_path
        end
    end

    local cwd = fs.cwd()
    local proofs_path = cwd .. "/models/" .. model_name .. "/proofs"
    local stat = fs.stat(proofs_path)
    if stat and stat.type == "directory" then
        return proofs_path
    end
    return nil  -- No proofs directory (not an error)
end

---Discover proof modules in a model's proofs directory.
---@param proofs_path string Absolute path to proofs directory
---@return table discovered Array of module names (without .lua extension)
local function discover_proofs(proofs_path)
    local discovered = {}
    local entries, err = fs.scandir(proofs_path)
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

---Register a single proof definition.
---Later loads override earlier loads (model layering).
---@param proof table Proof definition from module.proof
function M.register_proof(proof)
    if proof.disabled then
        -- Remove existing proof with this key (model suppression)
        if proof_by_key[proof.policy_key] then
            for i, existing in ipairs(proof_registry) do
                if existing.policy_key == proof.policy_key then
                    table.remove(proof_registry, i)
                    break
                end
            end
            proof_by_key[proof.policy_key] = nil
        end
        return
    end

    if proof_by_key[proof.policy_key] then
        -- Override: replace existing proof (model layering)
        for i, existing in ipairs(proof_registry) do
            if existing.policy_key == proof.policy_key then
                proof_registry[i] = proof
                break
            end
        end
    else
        table.insert(proof_registry, proof)
    end
    proof_by_key[proof.policy_key] = proof
end

---Create all proof SQL views in the database.
---@param data DataManager
function M.create_views(data)
    for _, proof in ipairs(proof_registry) do
        if proof.sql then
            data.db:exec_sql(proof.sql)
        end
    end
end

---Load proof modules from a model and register them.
---@param model_name string Name of the model (e.g., "default")
function M.load_model(model_name)
    local proofs_path = resolve_proofs_path(model_name)
    if not proofs_path then
        return  -- No proofs directory — model has no proofs
    end

    local modules = discover_proofs(proofs_path)
    local base_require = "models." .. model_name .. ".proofs"

    for _, mod_name in ipairs(modules) do
        local full_path = base_require .. "." .. mod_name
        local ok, module = pcall(require, full_path)
        if ok then
            if module.proof then
                M.register_proof(module.proof)
            end
        else
            error("Failed to load proof module: " .. full_path .. ": " .. tostring(module))
        end
    end
end

---Get all registered proofs (for verify_handler iteration).
---@return table[] Array of proof definitions
function M.get_proofs()
    return proof_registry
end

---Reset the registry (for testing).
function M.reset()
    proof_registry = {}
    proof_by_key = {}
end

return M
