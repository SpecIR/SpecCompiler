---FTS Indexer Handler for SpecCompiler.
---Populates FTS virtual tables for full-text search in the web app.
---Runs in EMIT phase before emitter to ensure FTS data is available
---when the postprocessor bundles the database.
---
---@module fts_indexer
local Queries = require("db.queries")

local M = {
    name = "fts_indexer",
    prerequisites = { "reqif_xhtml" }  -- Runs after ReqIF XHTML cache (if enabled)
}

-- ============================================================================
-- FTS Presence Checks and Schema Migration (for cached builds)
-- ============================================================================

-- INLINE SQL: PRAGMA and DDL (CREATE/DROP VIRTUAL TABLE) are schema ops, not data queries
local function table_has_column(data, table_name, col_name)
    local cols = data:query_all("PRAGMA table_info(" .. table_name .. ")")
    for _, c in ipairs(cols or {}) do
        if c.name == col_name then
            return true
        end
    end
    return false
end

local function ensure_fts_schema(data, log)
    -- Migrate older DBs where fts_floats/fts_attributes did not include spec_id.
    local needs_floats = not table_has_column(data, "fts_floats", "spec_id")
    local needs_attrs  = not table_has_column(data, "fts_attributes", "spec_id")

    if not needs_floats and not needs_attrs then
        return false
    end

    log = log or { info = function() end, warn = function() end }
    log.info("[FTS] Migrating FTS schema (adding spec_id columns)")

    if needs_floats then
        data:execute("DROP TABLE IF EXISTS fts_floats")
        data:execute([[
CREATE VIRTUAL TABLE fts_floats USING fts5(
  identifier UNINDEXED,
  float_type UNINDEXED,
  spec_id UNINDEXED,
  parent_ref UNINDEXED,
  caption,
  raw_source,
  tokenize='porter unicode61'
)]])
    end

    if needs_attrs then
        data:execute("DROP TABLE IF EXISTS fts_attributes")
        data:execute([[
CREATE VIRTUAL TABLE fts_attributes USING fts5(
  owner_ref UNINDEXED,
  spec_id UNINDEXED,
  attr_name UNINDEXED,
  attr_type UNINDEXED,
  attr_value,
  tokenize='porter unicode61'
)]])
    end

    return true
end

---Return true if FTS is present and matches current content counts for this spec.
---@param data DataManager
---@param spec_id string
---@return boolean
local function spec_fts_uptodate(data, spec_id)
    -- If the DB was created by an older version, these queries might fail.
    local function q(sql)
        local row = data:query_one(sql, { spec_id = spec_id })
        if not row then return nil end
        -- Normalize key across lsqlite3 named-values behavior.
        return row.c or row.count or row["COUNT(*)"]
    end

    local obj_total = q(Queries.search.count_objects_by_spec)
    local obj_fts   = q(Queries.search.count_fts_objects_by_spec)
    local fl_total  = q(Queries.search.count_floats_by_spec)
    local fl_fts    = q(Queries.search.count_fts_floats_by_spec)

    if obj_total == nil or obj_fts == nil or fl_total == nil or fl_fts == nil then
        return false
    end

    return (obj_total == obj_fts) and (fl_total == fl_fts)
end

-- ============================================================================
-- AST to Plain Text Conversion
-- ============================================================================

---Convert Pandoc AST JSON to plain text for FTS indexing.
---@param ast_json string|nil JSON-encoded Pandoc AST
---@return string Plain text content
local function ast_to_text(ast_json)
    if not ast_json or ast_json == "" then
        return ""
    end

    local ok, blocks = pcall(pandoc.json.decode, ast_json)
    if not ok or not blocks then
        return ""
    end

    -- Create a Pandoc document from blocks and stringify
    local doc = pandoc.Pandoc(blocks)
    return pandoc.utils.stringify(doc) or ""
end

-- ============================================================================
-- FTS Population Functions
-- ============================================================================

---Clear existing FTS data for a specification.
---@param data DataManager
---@param spec_id string Specification identifier
local function clear_fts_data(data, spec_id)
    data:execute(Queries.search.clear_fts_objects, { spec_id = spec_id })
    data:execute(Queries.search.clear_fts_attributes, { spec_id = spec_id })
    data:execute(Queries.search.clear_fts_floats, { spec_id = spec_id })
end

---Pre-fetch all float raw content for a spec, grouped by parent object.
---@param data DataManager
---@param spec_id string Specification identifier
---@return table Map of object_id -> concatenated raw_content
local function prefetch_float_content(data, spec_id)
    local floats = data:query_all(Queries.search.float_raw_content_by_spec,
        { spec_id = spec_id })

    local by_parent = {}
    for _, f in ipairs(floats or {}) do
        if f.parent_object_id then
            by_parent[f.parent_object_id] = by_parent[f.parent_object_id] or {}
            table.insert(by_parent[f.parent_object_id], f.raw_content)
        end
    end

    -- Concatenate raw sources per parent
    local result = {}
    for parent_id, sources in pairs(by_parent) do
        result[parent_id] = table.concat(sources, "\n")
    end
    return result
end

---Index spec objects into fts_objects.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
---@param float_content table Pre-fetched float content by parent object
local function index_objects(data, spec_id, log, float_content)
    local objects = data:query_all(Queries.search.get_objects_for_fts, { spec_id = spec_id })

    local count = 0
    for _, obj in ipairs(objects or {}) do
        local content = ast_to_text(obj.ast)

        -- Use pre-fetched float content (avoids N+1 query)
        local raw_source = float_content[obj.id] or ""

        -- Use label for navigation (matches HTML element ID)
        local nav_id = obj.label or obj.pid or tostring(obj.id)

        data:execute(Queries.search.insert_fts_object, {
            identifier = nav_id,
            object_type = obj.object_type,
            spec_id = obj.spec_id,
            title = obj.title or "",
            content = content,
            raw_source = raw_source
        })
        count = count + 1
    end

    log.debug("[FTS] Indexed %d objects for %s", count, spec_id)
end

---Index attributes into fts_attributes.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
local function index_attributes(data, spec_id, log)
    -- Query all attribute values for objects in this spec
    local attrs = data:query_all(Queries.search.get_attributes_for_fts, { spec_id = spec_id })

    local count = 0
    for _, attr in ipairs(attrs or {}) do
        -- Use string_value if available, otherwise extract from AST
        local value = attr.attr_value
        if (not value or value == "") and attr.ast then
            value = ast_to_text(attr.ast)
        end

        if value and value ~= "" then
            -- Only object-owned attributes are currently linkable in the UI.
            -- Skip nil owners to avoid polluting the index with anonymous rows.
            if not attr.owner_object_id then
                goto continue
            end
            data:execute(Queries.search.insert_fts_attribute, {
                owner_ref = attr.owner_object_id,
                spec_id = spec_id,
                attr_name = attr.attr_name,
                attr_type = attr.attr_type,
                attr_value = value
            })
            count = count + 1
        end
        ::continue::
    end

    log.debug("[FTS] Indexed %d attributes for %s", count, spec_id)
end

---Index floats into fts_floats.
---@param data DataManager
---@param spec_id string Specification identifier
---@param log table Logger
local function index_floats(data, spec_id, log)
    -- Query all floats with raw content
    local floats = data:query_all(Queries.search.get_floats_for_fts, { spec_id = spec_id })

    local count = 0
    for _, float in ipairs(floats or {}) do
        data:execute(Queries.search.insert_fts_float, {
            identifier = float.label or tostring(float.id),
            float_type = float.float_type,
            spec_id = spec_id,
            parent_ref = float.parent_ref or "",
            caption = float.caption or "",
            raw_source = float.raw_source or ""
        })
        count = count + 1
    end

    log.debug("[FTS] Indexed %d floats for %s", count, spec_id)
end

-- ============================================================================
-- EMIT Phase Handler
-- ============================================================================

---Populate FTS tables for full-text search.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_emit(data, contexts, diagnostics)
    local indexed = {}
    local log0 = (contexts and contexts[1] and contexts[1].log) or { info = function() end, warn = function() end }
    local migrated = ensure_fts_schema(data, log0)

    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id
        if not spec_id then
            goto continue
        end

        -- Avoid duplicate work if multiple outputs reference the same spec.
        if indexed[spec_id] then
            goto continue
        end
        indexed[spec_id] = true

        -- Cached builds can skip reindexing only if the index is present and
        -- matches current content (per-spec counts).
        if (not migrated) and ctx.cached and spec_fts_uptodate(data, spec_id) then
            goto continue
        end

        local log = ctx.log or { debug = function() end, info = function() end }

        log.info("[FTS] Building search index for %s", spec_id)

        -- Clear existing FTS data for this spec (outside transaction for FTS5 compatibility)
        clear_fts_data(data, spec_id)

        -- Pre-fetch float content to avoid N+1 queries
        local float_content = prefetch_float_content(data, spec_id)

        -- Use transaction for INSERT operations (dramatically improves performance)
        data:begin_transaction()

        -- Populate FTS tables
        index_objects(data, spec_id, log, float_content)
        index_attributes(data, spec_id, log)
        index_floats(data, spec_id, log)

        -- Commit transaction
        data:commit()

        log.info("[FTS] Search index complete for %s", spec_id)
        ::continue::
    end
end

return M
