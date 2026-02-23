---EAV Pivot Views for SpecCompiler.
-- Generates per-object-type views that pivot the EAV (Entity-Attribute-Value)
-- model into typed columns for external BI queries.
--
-- PURPOSE: These views are a convenience API for external consumers
-- (BI tools, ad-hoc SQL, custom model scripts). They are NOT used by any
-- internal pipeline code. All internal queries access the raw EAV tables
-- directly because they need raw_value, datatype, ast, enum_ref, typed
-- columns, COUNT/EXISTS checks, or cross-type operations that the
-- MAX()-based pivot cannot provide.
--
-- USAGE: Instead of:
--   SELECT o.pid, MAX(CASE WHEN a.name='status' THEN a.string_value END) AS status
--   FROM spec_objects o LEFT JOIN spec_attribute_values a ON a.owner_object_id = o.id
--   WHERE o.type_ref = 'HLR' GROUP BY o.id
--
-- External tools can write:
--   SELECT * FROM view_hlr_objects WHERE status = 'approved'
--
-- GENERATED VIEWS: One per non-composite object type, named view_{type}_objects.
-- Columns: id, specification_ref, pid, title_text, from_file, start_line,
-- end_line, level, label, plus one column per attribute defined for that type.
--
-- @see HLR-STOR-006

local DT = require("core.datatypes")

local M = {}

-- NOTE: Performance indexes for pivot views (idx_spec_attr_owner_name,
-- idx_spec_objects_type, idx_spec_floats_type) are defined in
-- src/db/schema/content.lua alongside all other content table indexes.

-- ============================================================================
-- DYNAMIC VIEW GENERATION
-- INLINE SQL: Views are dynamically generated from type metadata at runtime.
-- Column names and types come from spec_attribute_types — cannot be static.
-- ============================================================================

---Generate CREATE VIEW SQL for a specific object type.
---Pivots EAV spec_attribute_values into typed columns.
---@param type_id string The object type identifier (e.g., 'HLR', 'FD')
---@param attributes table Array of {name, datatype} attribute definitions
---@return string sql The CREATE VIEW SQL statement
function M.generate_object_type_view(type_id, attributes)
    local view_name = "view_" .. type_id:lower() .. "_objects"

    -- Build attribute column SELECT expressions
    local attr_columns = {}
    for _, attr in ipairs(attributes) do
        local col_expr
        local name = attr.name or attr.long_name

        -- Choose the appropriate typed column based on datatype
        if attr.datatype == DT.STRING or attr.datatype == DT.XHTML then
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.string_value END) AS %s",
                name, name
            )
        elseif attr.datatype == DT.INTEGER then
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.int_value END) AS %s",
                name, name
            )
        elseif attr.datatype == DT.REAL then
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.real_value END) AS %s",
                name, name
            )
        elseif attr.datatype == DT.BOOLEAN then
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.bool_value END) AS %s",
                name, name
            )
        elseif attr.datatype == DT.DATE then
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.date_value END) AS %s",
                name, name
            )
        elseif attr.datatype == DT.ENUM then
            -- For ENUM, join to get the key value
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN ev.key END) AS %s",
                name, name
            )
        else
            -- Fallback to string_value
            col_expr = string.format(
                "MAX(CASE WHEN av.name = '%s' THEN av.string_value END) AS %s",
                name, name
            )
        end
        table.insert(attr_columns, col_expr)
    end

    -- Build the full view SQL
    local attr_select = #attr_columns > 0 and ",\n  " .. table.concat(attr_columns, ",\n  ") or ""

    local sql = string.format([[
--------------------------------------------------------------------------------
-- Auto-generated view for %s objects
-- Pivots EAV attributes into typed columns for BI queries
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS %s AS
SELECT
  so.id,
  so.specification_ref,
  so.pid,
  so.title_text,
  so.from_file,
  so.start_line,
  so.end_line,
  so.level,
  so.label%s
FROM spec_objects so
LEFT JOIN spec_attribute_values av ON av.owner_object_id = so.id
LEFT JOIN enum_values ev ON av.enum_ref = ev.identifier
WHERE so.type_ref = '%s'
GROUP BY so.id;
]], type_id, view_name, attr_select, type_id)

    return sql
end

---Query attribute definitions for all object types.
---Returns query to get attributes grouped by owner type.
M.query_spec_attribute_types = [[
    SELECT
        ad.owner_type_ref,
        ad.long_name as name,
        dd.type as datatype
    FROM spec_attribute_types ad
    JOIN datatype_definitions dd ON ad.datatype_ref = dd.identifier
    ORDER BY ad.owner_type_ref, ad.long_name
]]

---Query all object types that should have pivot views.
M.query_object_types = [[
    SELECT identifier
    FROM spec_object_types
    WHERE is_composite = 0
    ORDER BY identifier
]]

---Initialize EAV pivot views.
---Queries spec_attribute_types and generates views for each object type.
---@param db table Database handler with :execute and :query_all methods
function M.initialize(db)
    -- Get all object types (non-composite)
    local types = db:query_all(M.query_object_types) or {}

    -- Get all attribute definitions
    local attrs = db:query_all(M.query_spec_attribute_types) or {}

    -- Group attributes by owner type
    local attrs_by_type = {}
    for _, attr in ipairs(attrs) do
        local type_ref = attr.owner_type_ref
        if not attrs_by_type[type_ref] then
            attrs_by_type[type_ref] = {}
        end
        table.insert(attrs_by_type[type_ref], attr)
    end

    -- Generate and execute view for each type
    for _, type_row in ipairs(types) do
        local type_id = type_row.identifier
        local type_attrs = attrs_by_type[type_id] or {}
        local view_sql = M.generate_object_type_view(type_id, type_attrs)
        db:execute(view_sql)
    end
end

return M
