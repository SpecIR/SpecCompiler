---View Materializer for SpecCompiler.
---Pre-computes view data during TRANSFORM phase for efficient rendering.
---
---This handler queries the database and stores structured data in
---spec_views.resolved_data as JSON. View renderers then use this
---pre-computed data instead of making DB queries at render time.
---
---@module view_materializer
local Queries = require("db.queries")

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

-- Cache for view type lookups
local view_counter_group_cache = {}
local view_abbrev_type_cache = {}

---Get the counter_group for a view name by querying spec_view_types.
---Returns the counter_group if this view is a "list of floats" type.
---@param data DataManager
---@param view_name string View name (e.g., "lof", "lot")
---@return string|nil counter_group The counter_group, or nil if not a list view
local function get_view_counter_group(data, view_name)
    local lower_name = view_name:lower()

    if view_counter_group_cache[lower_name] ~= nil then
        return view_counter_group_cache[lower_name] or nil
    end

    -- Query spec_view_types for counter_group (list-of-X views)
    local result = data:query_one(Queries.materialization.select_counter_group_by_view,
        { view_name = lower_name })

    if result and result.counter_group then
        view_counter_group_cache[lower_name] = result.counter_group
        return result.counter_group
    end

    view_counter_group_cache[lower_name] = false  -- Cache negative result
    return nil
end

---Get the view_subtype_ref for abbreviation-style views.
---Queries spec_view_types for views that have view_subtype_ref set.
---@param data DataManager
---@param view_name string View name (e.g., "abbrev_list", "sigla_list")
---@return string|nil view_subtype_ref The view subtype ref, or nil if not an abbrev view
local function get_abbrev_view_type(data, view_name)
    local lower_name = view_name:lower()

    if view_abbrev_type_cache[lower_name] ~= nil then
        return view_abbrev_type_cache[lower_name] or nil
    end

    -- Query spec_view_types for abbreviation-style views
    -- These have view_subtype_ref set (e.g., points to ABBREV, SIGLA, etc.)
    local result = data:query_one(Queries.materialization.select_subtype_ref_by_view,
        { view_name = lower_name })

    if result and result.view_subtype_ref then
        view_abbrev_type_cache[lower_name] = result.view_subtype_ref
        return result.view_subtype_ref
    end

    view_abbrev_type_cache[lower_name] = false  -- Cache negative result
    return nil
end

-- Cache for materializer type lookups
local view_materializer_type_cache = {}

---Get the materializer_type for a view name.
---Queries spec_view_types for the materialization strategy.
---@param data DataManager
---@param view_name string View name (e.g., "toc", "lof")
---@return string|nil materializer_type The materializer type (e.g., "toc", "lof", "abbrev_list")
local function get_view_materializer_type(data, view_name)
    local lower_name = view_name:lower()

    if view_materializer_type_cache[lower_name] ~= nil then
        return view_materializer_type_cache[lower_name] or nil
    end

    -- Query spec_view_types for materializer_type
    local result = data:query_one(Queries.materialization.select_materializer_type_by_view,
        { view_name = lower_name })

    if result and result.materializer_type then
        view_materializer_type_cache[lower_name] = result.materializer_type
        return result.materializer_type
    end

    view_materializer_type_cache[lower_name] = false  -- Cache negative result
    return nil
end

---Clear module-level caches (required for re-entrant engine.run_project calls).
function M.clear_cache()
    view_counter_group_cache = {}
    view_abbrev_type_cache = {}
    view_materializer_type_cache = {}
end

-- ============================================================================
-- Transform Phase
-- ============================================================================

---Encode entries array as JSON.
---@param entries table Array of table entries
---@return string json JSON string
local function encode_as_json(entries)
    return pandoc.json.encode(entries)
end

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
                local json_data = encode_as_json(entries)
                data:execute(Queries.materialization.update_view_resolved_data,
                    { id = view.id, data = json_data })
            end
        end
    end
    data:commit()
end

return M
