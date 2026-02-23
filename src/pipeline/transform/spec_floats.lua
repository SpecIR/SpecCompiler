---Spec Floats Transform Handler for SpecCompiler.
---Handles TRANSFORM phase: resolves internal float types (TABLE, CSV, etc.)
---External floats (PLANTUML, DOT, MERMAID, CHART) are handled by external_render_handler.
---
---@module spec_floats
local hash_utils = require('infra.hash_utils')

-- FloatResolver class for internal float resolution
local FloatResolver = {}

-- Cache for loaded float type modules
local float_type_modules = {}

-- Data manager reference (set by new() for database access)
local data_manager = nil

---Load a float type module dynamically using database-driven discovery.
---Resolves aliases to canonical type, then tries model-specific and default paths.
---@param type_ref string Float type (e.g., "TABLE", "CSV", "LISTTABLE")
---@param model_name string|nil Model name (defaults to "default")
---@return table|nil module with transform function
local function get_float_type_module(type_ref, model_name)
    local upper = type_ref:upper()
    model_name = model_name or "default"

    -- Check cache (returns module or false for cached negative)
    local cache_key = upper .. ":" .. model_name
    if float_type_modules[cache_key] ~= nil then
        return float_type_modules[cache_key] or nil
    end

    -- Resolve aliases to canonical type via database
    local canonical = upper
    if data_manager then
        local type_def = data_manager:query_one([[
            SELECT identifier FROM spec_float_types
            WHERE identifier = :type_ref
               OR (aliases IS NOT NULL AND aliases LIKE :pattern)
        ]], {
            type_ref = upper,
            pattern = "%," .. type_ref:lower() .. ",%"
        })

        if type_def then
            canonical = type_def.identifier
        end
    end

    -- Try model-specific path first, then default
    local paths = {
        "models." .. model_name .. ".types.floats." .. canonical:lower(),
        "models.default.types.floats." .. canonical:lower()
    }

    for _, module_path in ipairs(paths) do
        local ok, module = pcall(require, module_path)
        if ok and module and module.transform then
            float_type_modules[cache_key] = module
            return module
        end
    end

    float_type_modules[cache_key] = false
    return nil
end

function FloatResolver.new(data, build_dir, log)
    -- Store data manager reference for dynamic module discovery
    data_manager = data

    local self = {
        data = data,
        build_dir = build_dir or "build",
        log = log
    }
    return setmetatable(self, { __index = FloatResolver })
end

---Get floats that need resolution for a specification
---@param spec_id string Specification ID
---@return table floats Array of float records
function FloatResolver:get_pending_floats(spec_id)
    -- Get ALL floats that need resolution (both external and internal)
    return self.data:query_all([[
        SELECT id, type_ref, syntax_key, from_file, raw_content, content_sha, resolved_ast
        FROM spec_floats
        WHERE specification_ref = :spec
          AND (resolved_ast IS NULL OR content_sha IS NULL)
    ]], { spec = spec_id }) or {}
end

---Check if float has cached resolution
---@param content_sha string SHA of float content
---@return string|nil resolved_path Cached output path or nil
function FloatResolver:get_cached(content_sha)
    if not content_sha then return nil end

    local cached = self.data:query_one([[
        SELECT resolved_ast FROM spec_floats
        WHERE content_sha = :sha AND resolved_ast IS NOT NULL
        LIMIT 1
    ]], { sha = content_sha })

    return cached and cached.resolved_ast or nil
end


---Resolve a float using internal Lua transform
---@param float table Float record
---@return boolean success
---@return string status "cached" | "resolved" | nil
function FloatResolver:resolve_internal(float)
    local module = get_float_type_module(float.type_ref)
    if not module then
        return false
    end

    local content_sha = hash_utils.sha1(float.raw_content or "")

    -- Check cache first
    local cached = self:get_cached(content_sha)
    if cached then
        self.data:execute([[
            UPDATE spec_floats SET content_sha = :sha, resolved_ast = :ast
            WHERE id = :id
        ]], { id = float.id, sha = content_sha, ast = cached })
        return true, "cached"
    end

    -- Transform using module
    local ast = module.transform(float.raw_content, float.type_ref, self.log)
    if not ast then
        if self.log then
            self.log.warn("Internal transform failed for %s '%s' from %s",
                float.type_ref or "unknown", float.syntax_key or tostring(float.id), float.from_file or "unknown")
        end
        return false
    end

    -- Encode AST to JSON
    local ast_json = pandoc.json.encode(ast)

    -- Store in database
    self.data:execute([[
        UPDATE spec_floats SET content_sha = :sha, resolved_ast = :ast
        WHERE id = :id
    ]], { id = float.id, sha = content_sha, ast = ast_json })

    return true, "resolved"
end

---Resolve all pending floats for a specification
---Only handles internal transforms (TABLE, CSV, etc.)
---External floats (PLANTUML, CHART, etc.) are handled by external_render_handler
---@param spec_id string Specification ID
---@return number resolved Count of resolved floats
---@return number cached Count of cache hits
function FloatResolver:resolve_all(spec_id)
    local floats = self:get_pending_floats(spec_id)
    if #floats == 0 then
        return 0, 0
    end

    local resolved = 0
    local cached = 0

    for _, float in ipairs(floats) do
        local type_ref = (float.type_ref or ""):upper()

        if get_float_type_module(type_ref) then
            -- Internal resolver (TABLE, CSV, etc.)
            local ok, status = self:resolve_internal(float)
            if ok then
                if status == "cached" then
                    cached = cached + 1
                else
                    resolved = resolved + 1
                end
            end
        end
        -- External floats (PLANTUML, CHART, etc.) are handled by external_render_handler
    end

    if self.log and (resolved > 0 or cached > 0) then
        self.log.info("Float resolution: %d resolved, %d cached", resolved, cached)
    end

    return resolved, cached
end

-- Handler module (combines FloatResolver with pipeline registration)
local M = {
    name = "spec_floats_transform",
    prerequisites = {}  -- Runs in TRANSFORM phase
}

---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"
        local build_dir = ctx.build_dir or "build"

        local resolver = FloatResolver.new(data, build_dir, ctx.log)
        local resolved, cached = resolver:resolve_all(spec_id)

        -- Store resolution stats in context
        ctx.float_resolution = {
            resolved = resolved,
            cached = cached
        }

        if ctx.log and (resolved > 0 or cached > 0) then
            ctx.log.info("Float resolution: %d resolved, %d from cache", resolved, cached)
        end
    end
end

-- Export FloatResolver class for direct use if needed
M.FloatResolver = FloatResolver

return M
