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
