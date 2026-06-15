---View Materializer for SpecCompiler.
---Pre-computes view data during TRANSFORM phase for efficient rendering.
---
---This handler queries the database and stores structured data in
---spec_views.resolved_data as JSON. View renderers then use this
---pre-computed data instead of making DB queries at render time.
---
---@module view_materializer
local Queries = require("db.queries")
local cache_registry = require("pipeline.shared.cache_registry")

local M = {
    name = "view_materializer",
    prerequisites = {"spec_views"}  -- Must run after views are registered
}

-- ============================================================================
-- Materialization Functions
-- ============================================================================

---Materialize TOC entries from spec_objects.
---@param data DataManager
---@param spec_id string
---@param options table {max_level = 3}
---@return table entries Array of {pid, title_text, level, identifier}
local function materialize_toc(data, spec_id, options)
    local max_level = options.max_level or 3

    return data:query_all(Queries.materialization.select_toc_entries,
        { spec_id = spec_id, max_level = max_level }) or {}
end

---Materialize list of floats by counter_group.
---Uses counter_group from spec_float_types for shared numbering groups.
---@param data DataManager
---@param spec_id string
---@param counter_group string The counter_group to filter by (e.g., "FIGURE", "TABLE")
---@return table entries Array of {identifier, caption, number, label}
local function materialize_list_of_floats(data, spec_id, counter_group)
    -- Only include floats that have captions in LOT/LOF
    -- Floats without captions (e.g., revision-sheet) are excluded
    return data:query_all(Queries.materialization.select_floats_by_counter_group,
        { spec_id = spec_id, counter_group = counter_group }) or {}
end

---Materialize abbreviation list entries by view_type_ref.
---Uses dynamic lookup from spec_view_types.
---@param data DataManager
---@param spec_id string
---@param view_type_ref string The view type to filter by (e.g., "SIGLA", "ABBREV")
---@return table entries Array of abbreviation entries
local function materialize_abbrev_list(data, spec_id, view_type_ref)
    return data:query_all(Queries.materialization.select_abbrev_entries,
        { spec_id = spec_id, view_type_ref = view_type_ref }) or {}
end

-- Caches for view type lookups (false = cached negative result)
local view_counter_group_cache = {}
local view_abbrev_type_cache = {}
local view_materializer_type_cache = {}

---Cached spec_view_types lookup: query once per view name, remember misses.
---@param cache table Cache table keyed by lowercase view name
---@param data DataManager
---@param view_name string View name (e.g., "toc", "lof", "sigla_list")
---@param query string Queries.materialization.* SQL taking {view_name}
---@param field string Result field to return (e.g., "counter_group")
---@return string|nil value The field value, or nil if not that kind of view
local function cached_view_lookup(cache, data, view_name, query, field)
    local lower_name = view_name:lower()
    if cache[lower_name] ~= nil then
        return cache[lower_name] or nil
    end
    local result = data:query_one(query, { view_name = lower_name })
    local value = result and result[field] or nil
    cache[lower_name] = value or false
    return value
end

---Get the counter_group for a view name ("list of floats" views, e.g. lof/lot).
local function get_view_counter_group(data, view_name)
    return cached_view_lookup(view_counter_group_cache, data, view_name,
        Queries.materialization.select_counter_group_by_view, "counter_group")
end

---Get the view_subtype_ref for abbreviation-style views (e.g. abbrev_list).
local function get_abbrev_view_type(data, view_name)
    return cached_view_lookup(view_abbrev_type_cache, data, view_name,
        Queries.materialization.select_subtype_ref_by_view, "view_subtype_ref")
end

---Get the materializer_type for a view name (materialization strategy).
local function get_view_materializer_type(data, view_name)
    return cached_view_lookup(view_materializer_type_cache, data, view_name,
        Queries.materialization.select_materializer_type_by_view, "materializer_type")
end

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    view_counter_group_cache = {}
    view_abbrev_type_cache = {}
    view_materializer_type_cache = {}
end
cache_registry.register(M.clear_cache)

-- ============================================================================
-- Transform Phase
-- ============================================================================

---Pre-compute view data and store in resolved_data column.
---Model-agnostic: uses inline_prefix to identify inline view entries.
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    data:begin_transaction()
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        -- Get all views with inline_prefix that need materialization
        -- This is model-agnostic - core has no knowledge of specific type names like 'SELECT'
        local views = data:query_all(Queries.materialization.select_views_needing_materialization,
            { spec_id = spec_id })

        for _, view in ipairs(views or {}) do
            local view_name = view.view_type_ref
            if type(view_name) == "string" then
                view_name = view_name:lower()
            end

            local entries = nil

            -- Try different materialization strategies using materializer_type lookup
            local mat_type = get_view_materializer_type(data, view_name)

            if mat_type == "toc" then
                -- Table of Contents
                entries = materialize_toc(data, spec_id, {})
            elseif mat_type == "lof" or mat_type == "lot" then
                -- List of Floats - lookup counter_group
                local counter_group = get_view_counter_group(data, view_name)
                if counter_group then
                    entries = materialize_list_of_floats(data, spec_id, counter_group)
                end
            elseif mat_type == "abbrev_list" then
                -- Abbreviation list - lookup view_subtype_ref
                local abbrev_type = get_abbrev_view_type(data, view_name)
                if abbrev_type then
                    entries = materialize_abbrev_list(data, spec_id, abbrev_type)
                end
            end

            -- Store materialized data if we got entries
            if entries then
                local json_data = pandoc.json.encode(entries)
                data:execute(Queries.materialization.update_view_resolved_data,
                    { id = view.id, data = json_data })
            end
        end
    end
    data:commit()
end

return M
