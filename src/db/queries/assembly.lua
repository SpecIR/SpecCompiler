---Assembly queries for SpecCompiler.
-- Queries for document assembly (fetching objects, floats, views, attributes
-- in order for output generation).

local M = {}

-- ============================================================================
-- Specifications
-- ============================================================================

-- Get specification info including rendered header for document assembly
M.select_specification = [[
    SELECT identifier, root_path, long_name, type_ref, pid, header_ast, body_ast
    FROM specifications
    WHERE identifier = :spec_id
]]

-- ============================================================================
-- Spec Objects
-- ============================================================================

-- Get all spec objects for a specification ordered by file sequence
-- Level 1 headers are specifications (in specifications table),
-- not spec_objects, so only level 2+ content is assembled here.
-- ORDER BY file_seq preserves document order (not from_file which would sort alphabetically)
M.select_objects_by_spec = [[
    SELECT id, type_ref, from_file, file_seq, pid, title_text,
           label, level, start_line, end_line, ast
    FROM spec_objects
    WHERE specification_ref = :spec_id
    ORDER BY file_seq
]]

-- Get a single spec_object AST by id (for incremental assembly or previews)
M.select_object_ast = [[
    SELECT ast FROM spec_objects WHERE id = :id
]]

-- ============================================================================
-- Spec Floats
-- ============================================================================

-- Get all floats for a specification with type info, ordered by file sequence
M.select_floats_by_spec = [[
    SELECT f.id, f.type_ref, f.label, f.anchor, f.number, f.caption, f.pandoc_attributes,
           f.raw_content, f.resolved_ast, f.from_file,
           ft.caption_format, ft.counter_group
    FROM spec_floats f
    LEFT JOIN spec_float_types ft ON f.type_ref = ft.identifier
    WHERE f.specification_ref = :spec_id
    ORDER BY f.file_seq
]]

-- ============================================================================
-- Spec Views
-- ============================================================================

-- Get all views for a specification ordered by file sequence
M.select_views_by_spec = [[
    SELECT id, view_type_ref, raw_ast, resolved_ast
    FROM spec_views
    WHERE specification_ref = :spec_id
    ORDER BY file_seq
]]

-- ============================================================================
-- Attribute Values
-- ============================================================================

-- Get all attribute values for a specification (for document metadata)
M.select_attributes_by_spec = [[
    SELECT name, raw_value, datatype,
           COALESCE(string_value, int_value, real_value, bool_value, date_value) AS typed_value
    FROM spec_attribute_values
    WHERE specification_ref = :spec_id
]]

return M
