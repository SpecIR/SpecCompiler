---Materialization queries for SpecCompiler.
-- Queries for view materialization (TOC, LOF, abbreviations, etc.).

local M = {}

-- ============================================================================
-- View Type Lookups
-- ============================================================================

-- Get counter_group for a view type (list-of-X views like LOF, LOT)
M.select_counter_group_by_view = [[
    SELECT counter_group FROM spec_view_types
    WHERE LOWER(identifier) = :view_name
      AND counter_group IS NOT NULL
]]

-- Get view_subtype_ref for abbreviation-style views
M.select_subtype_ref_by_view = [[
    SELECT view_subtype_ref FROM spec_view_types
    WHERE LOWER(identifier) = :view_name
      AND view_subtype_ref IS NOT NULL
]]

-- Get materializer_type for a view type
M.select_materializer_type_by_view = [[
    SELECT materializer_type FROM spec_view_types
    WHERE LOWER(identifier) = :view_name
      AND materializer_type IS NOT NULL
]]

-- ============================================================================
-- Materialization Data Queries
-- ============================================================================

-- Get TOC entries from spec_objects for a specification
M.select_toc_entries = [[
    SELECT pid, title_text, level, id, label FROM spec_objects
    WHERE specification_ref = :spec_id
      AND level > 0
      AND level <= :max_level
    ORDER BY file_seq
]]

-- Get floats by counter_group for list-of-floats views (LOF, LOT)
M.select_floats_by_counter_group = [[
    SELECT f.id, f.caption, f.number, f.label
    FROM spec_floats f
    JOIN spec_float_types ft ON f.type_ref = ft.identifier
    WHERE f.specification_ref = :spec_id
      AND COALESCE(ft.counter_group, ft.identifier) = :counter_group
      AND f.caption IS NOT NULL AND f.caption != ''
    ORDER BY f.file_seq
]]

-- Get abbreviation entries from spec_views by view_type_ref
M.select_abbrev_entries = [[
    SELECT raw_ast as content FROM spec_views
    WHERE specification_ref = :spec_id
      AND view_type_ref = :view_type_ref
    ORDER BY file_seq
]]

-- ============================================================================
-- Transform Phase Queries
-- ============================================================================

-- Get views with inline_prefix that need materialization
M.select_views_needing_materialization = [[
    SELECT sv.id, sv.view_type_ref, sv.raw_ast FROM spec_views sv
    JOIN spec_view_types svt ON sv.view_type_ref = svt.identifier
    WHERE sv.specification_ref = :spec_id
      AND svt.inline_prefix IS NOT NULL
      AND sv.resolved_data IS NULL
]]

-- Store materialized data (JSON) into a view's resolved_data column
M.update_view_resolved_data = [[
    UPDATE spec_views SET resolved_data = :data
    WHERE id = :id
]]

return M
