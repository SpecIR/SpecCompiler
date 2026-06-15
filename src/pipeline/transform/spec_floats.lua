---Spec Floats Transform Handler for SpecCompiler.
---Handles TRANSFORM phase: resolves internal float types (TABLE, CSV, etc.)
---External floats (PLANTUML, DOT, MERMAID, CHART) are handled by external_render_handler.
---
---@module spec_floats
local hash_utils = require('infra.hash_utils')
local registry = require('contract.registry')
local hook_ctx = require('pipeline.shared.hook_ctx')

-- FloatResolver class for internal float resolution
local FloatResolver = {}

-- Data manager reference (set by new() for database access)
local data_manager = nil

-- Cache: float-type alias (UPPER) -> canonical float-type id. Alias resolution
-- is stable across runs; the transform hook itself is read fresh from the host.
local canonical_cache = {}

---Resolve the internal-transform hook for a float type from the host hook index.
---Resolves aliases to the canonical type via the database, then reads
---host:get_hook("float", id, "transform").
---@param type_ref string Float type (e.g., "TABLE", "CSV", "LISTTABLE")
---@return function|nil transform fn(raw_content, type_ref, log) -> Pandoc block
local function get_float_transform(type_ref)
    local upper = type_ref:upper()

    local canonical = canonical_cache[upper]
    if canonical == nil then
        canonical = upper
        if data_manager then
            local type_def = data_manager:query_one([[
                SELECT identifier FROM spec_float_types
                WHERE identifier = :type_ref
                   OR (aliases IS NOT NULL AND aliases LIKE :pattern)
            ]], {
                type_ref = upper,
                pattern = "%," .. type_ref:lower() .. ",%"
            })
            if type_def then canonical = type_def.identifier end
        end
        canonical_cache[upper] = canonical
    end

    local host = registry.current()
    -- Inherited lookup: a float extending another inherits its transform hook,
    -- consistent with every other hook dispatch path.
    return host and host:get_hook_inherited("float", canonical, "transform") or nil
end

function FloatResolver.new(data, log, diagnostics)
    -- Store data manager reference for dynamic module discovery
    data_manager = data

    local self = {
        data = data,
        log = log,
        diagnostics = diagnostics
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
    local transform = get_float_transform(float.type_ref)
    if not transform then
        return false
    end

    -- The cache key covers everything a transform may depend on: raw content,
    -- the source file (FIGURE resolves image paths relative to it), and the
    -- float's attributes (LISTING reads its language attr). This keeps the
    -- cross-float resolved-AST reuse correct for every internal float type.
    local content_sha = hash_utils.sha1(table.concat({
        float.raw_content or "", float.from_file or "", float.pandoc_attributes or "",
    }, "\0"))

    -- Check cache first
    local cached = self:get_cached(content_sha)
    if cached then
        self.data:execute([[
            UPDATE spec_floats SET content_sha = :sha, resolved_ast = :ast
            WHERE id = :id
        ]], { id = float.id, sha = content_sha, ast = cached })
        return true, "cached"
    end

    -- The transform DATA hook returns the resolved_ast as a ready-to-store STRING:
    -- each internal float type encodes its own format (Pandoc-AST JSON for TABLE,
    -- a custom JSON for LISTING, TeX text for MATH, png-path JSON for FIGURE). It
    -- reads its inputs off dctx.subject (raw_content/float) and the DB off dctx.data.
    local dctx = hook_ctx.build_data({ log = self.log }, self.data, self.diagnostics,
        { raw_content = float.raw_content, float = float }, "transform", float.specification_ref)
    local resolved = transform(dctx)
    if not resolved then
        if self.log then
            self.log.warn("Internal transform failed for %s '%s' from %s",
                float.type_ref or "unknown", float.syntax_key or tostring(float.id), float.from_file or "unknown")
        end
        return false
    end

    self.data:execute([[
        UPDATE spec_floats SET content_sha = :sha, resolved_ast = :ast
        WHERE id = :id
    ]], { id = float.id, sha = content_sha, ast = resolved })

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
        -- Internal resolver (TABLE, CSV, etc.); resolve_internal is a no-op for
        -- types without a transform hook. External floats (PLANTUML, CHART,
        -- etc.) are handled by external_render_handler.
        local ok, status = self:resolve_internal(float)
        if ok then
            if status == "cached" then
                cached = cached + 1
            else
                resolved = resolved + 1
            end
        end
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

        local resolver = FloatResolver.new(data, ctx.log, diagnostics)
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

return M
