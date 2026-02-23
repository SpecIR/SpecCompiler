---Content queries for SpecCompiler.
-- INSERT/SELECT operations for specifications, spec_objects, spec_floats,
-- spec_relations, spec_views, spec_attribute_values.

local M = {}

-- ============================================================================
-- Bulk Delete (initialize phase cleanup)
-- ============================================================================

-- Delete all spec objects for a specification
M.delete_objects_by_spec = [[
    DELETE FROM spec_objects WHERE specification_ref = :spec_id
]]

-- Delete all attribute values for a specification
M.delete_attributes_by_spec = [[
    DELETE FROM spec_attribute_values WHERE specification_ref = :spec_id
]]

-- Delete all views for a specification
M.delete_views_by_spec = [[
    DELETE FROM spec_views WHERE specification_ref = :spec_id
]]

-- Delete all relations for a specification
M.delete_relations_by_spec = [[
    DELETE FROM spec_relations WHERE specification_ref = :spec_id
]]

-- ============================================================================
-- View Type Cache (initialize phase)
-- ============================================================================

-- Get view types with inline prefixes for cache building
M.select_view_types_with_prefix = [[
    SELECT identifier, inline_prefix, aliases, needs_external_render
    FROM spec_view_types
    WHERE inline_prefix IS NOT NULL
]]

-- ============================================================================
-- Spec Objects
-- ============================================================================

M.insert_object = [[
    INSERT INTO spec_objects (
        content_sha, specification_ref, type_ref, from_file, file_seq,
        pid, pid_prefix, pid_sequence, pid_auto_generated,
        title_text, label, level, start_line, end_line, ast
    ) VALUES (
        :content_sha, :specification_ref, :type_ref, :from_file, :file_seq,
        :pid, :pid_prefix, :pid_sequence, :pid_auto_generated,
        :title_text, :label, :level, :start_line, :end_line, :ast
    )
]]

-- Get objects by specification and type
M.objects_by_spec_type = [[
    SELECT id, pid, title_text, label
    FROM spec_objects
    WHERE specification_ref = :spec_id AND type_ref = :type_ref
]]

-- Get objects with AST for transformation
M.objects_with_ast = [[
    SELECT id, ast FROM spec_objects
    WHERE specification_ref = :spec_id AND ast IS NOT NULL
]]

-- Update object AST
M.update_object_ast = [[
    UPDATE spec_objects SET ast = :ast WHERE id = :id
]]

-- ============================================================================
-- Spec Objects (lookups)
-- ============================================================================

-- Get object PID by integer id
M.select_object_pid_by_id = [[
    SELECT pid FROM spec_objects WHERE id = :id
]]

-- ============================================================================
-- Spec Floats
-- ============================================================================

-- Delete all floats for a specification (used before re-insert)
M.delete_floats_by_spec = [[
    DELETE FROM spec_floats WHERE specification_ref = :spec_id
]]

-- Insert a spec_float with all columns
M.insert_float = [[
    INSERT INTO spec_floats (
        content_sha, specification_ref, type_ref, from_file, file_seq, start_line,
        label, number, caption, raw_content, raw_ast, parent_object_id,
        pandoc_attributes, anchor, syntax_key
    ) VALUES (
        :content_sha, :specification_ref, :type_ref, :from_file, :file_seq, :start_line,
        :label, :number, :caption, :raw_content, :raw_ast, :parent_object_id,
        :pandoc_attributes, :anchor, :syntax_key
    )
]]

-- Get cached float resolution by content SHA
M.select_float_cached_resolution = [[
    SELECT resolved_ast FROM spec_floats
    WHERE content_sha = :sha AND resolved_ast IS NOT NULL
    LIMIT 1
]]

-- Update float resolved_ast
M.update_float_resolved = [[
    UPDATE spec_floats SET resolved_ast = :ast WHERE id = :id
]]

-- ============================================================================
-- Spec Views
-- ============================================================================

-- Insert a spec_view
M.insert_view = [[
    INSERT INTO spec_views (
        content_sha, specification_ref, view_type_ref, from_file, file_seq, start_line, raw_ast
    ) VALUES (
        :content_sha, :specification_ref, :view_type_ref, :from_file, :file_seq, :start_line, :raw_ast
    )
]]

-- Get views needing transformation (resolved_ast is NULL)
M.views_needing_transform = [[
    SELECT id, raw_ast FROM spec_views
    WHERE specification_ref = :spec_id
      AND view_type_ref = :view_type
      AND resolved_ast IS NULL
]]

-- Get views by type and spec
M.views_by_type = [[
    SELECT raw_ast FROM spec_views
    WHERE specification_ref = :spec_id
      AND view_type_ref = :view_type
    ORDER BY file_seq
]]

-- Update view resolved_ast
M.update_view_resolved = [[
    UPDATE spec_views SET resolved_ast = :resolved WHERE id = :id
]]

-- Get view resolved_ast by ID
M.view_resolved_by_id = [[
    SELECT resolved_ast FROM spec_views
    WHERE id = :id
      AND resolved_ast IS NOT NULL
]]

-- Get view resolved_ast by expression match (fallback)
M.view_resolved_by_expr = [[
    SELECT resolved_ast FROM spec_views
    WHERE specification_ref = :spec_id
      AND view_type_ref = :view_type
      AND raw_ast = :expr
      AND resolved_ast IS NOT NULL
    LIMIT 1
]]

-- ============================================================================
-- Attribute Values
-- ============================================================================

-- Insert attribute value (all typed columns)
M.insert_attribute_value = [[
    INSERT INTO spec_attribute_values (
        content_sha, specification_ref, owner_object_id, owner_float_id,
        name, raw_value,
        string_value, int_value, real_value, bool_value, date_value,
        enum_ref, ast, datatype
    ) VALUES (
        :content_sha, :specification_ref, :owner_object_id, :owner_float_id,
        :name, :raw_value,
        :string_value, :int_value, :real_value, :bool_value, :date_value,
        :enum_ref, :ast, :datatype
    )
]]

-- ============================================================================
-- Attribute Casting
-- ============================================================================

-- Get all attributes that need casting (raw_value present, no typed value yet)
M.pending_attribute_casts = [[
    SELECT
        av.id,
        av.raw_value,
        av.datatype,
        ad.datatype_ref
    FROM spec_attribute_values av
    LEFT JOIN spec_objects so ON av.owner_object_id = so.id
    LEFT JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
        AND ad.long_name = av.name
    WHERE av.raw_value IS NOT NULL
      AND av.string_value IS NULL
      AND av.int_value IS NULL
      AND av.real_value IS NULL
      AND av.bool_value IS NULL
      AND av.date_value IS NULL
      AND av.enum_ref IS NULL
]]

-- Build UPDATE for attribute casting with dynamic typed columns.
-- Returns SQL string for updating specific typed columns by id.
---@param columns string[] Column names to update (e.g., {"string_value"})
---@return string sql Parameterized UPDATE statement
function M.build_attribute_cast_update(columns)
    local sets = {}
    for _, col in ipairs(columns) do
        sets[#sets + 1] = col .. " = :" .. col
    end
    return "UPDATE spec_attribute_values SET " ..
        table.concat(sets, ", ") .. " WHERE id = :id"
end

-- Get attribute values by owner object ID
M.select_attributes_by_owner = [[
    SELECT name, string_value, raw_value, ast
    FROM spec_attribute_values
    WHERE owner_object_id = :owner_id
]]

-- Get attribute values with AST for link rewriting (TRANSFORM phase)
M.attributes_with_ast = [[
    SELECT av.id, av.owner_object_id, av.ast
    FROM spec_attribute_values av
    WHERE av.specification_ref = :spec_id
      AND av.ast IS NOT NULL
      AND av.owner_object_id IS NOT NULL
]]

-- Update attribute AST after link rewriting
M.update_attribute_ast = [[
    UPDATE spec_attribute_values SET ast = :ast WHERE id = :id
]]

-- Get XHTML attributes needing conversion for ReqIF
M.select_xhtml_attributes_by_spec = [[
    SELECT id, ast
    FROM spec_attribute_values
    WHERE specification_ref = :spec_id
      AND datatype = 'XHTML'
      AND ast IS NOT NULL
      AND ast != ''
]]

-- Update attribute XHTML value (ReqIF cache)
M.update_attribute_xhtml = [[
    UPDATE spec_attribute_values
    SET xhtml_value = :xhtml_value
    WHERE id = :id
]]

-- ============================================================================
-- Float Numbering
-- ============================================================================

-- Get distinct counter groups for float numbering
M.distinct_counter_groups = [[
    SELECT DISTINCT COALESCE(ft.counter_group, ft.identifier) as counter_group
    FROM spec_floats f
    JOIN spec_float_types ft ON f.type_ref = ft.identifier
    ORDER BY counter_group
]]

-- Get float IDs by counter group for numbering (only captioned floats)
M.floats_by_counter_group_for_numbering = [[
    SELECT f.id
    FROM spec_floats f
    JOIN spec_float_types ft ON f.type_ref = ft.identifier
    WHERE COALESCE(ft.counter_group, ft.identifier) = :counter_group
      AND f.caption IS NOT NULL AND f.caption != ''
    ORDER BY f.file_seq
]]

-- Get distinct counter groups for float numbering within a specification
M.distinct_counter_groups_by_spec = [[
    SELECT DISTINCT COALESCE(ft.counter_group, ft.identifier) as counter_group
    FROM spec_floats f
    JOIN spec_float_types ft ON f.type_ref = ft.identifier
    WHERE f.specification_ref = :spec_id
    ORDER BY counter_group
]]

-- Get float IDs by counter group for numbering within a specification (only captioned floats)
M.floats_by_counter_group_by_spec = [[
    SELECT f.id
    FROM spec_floats f
    JOIN spec_float_types ft ON f.type_ref = ft.identifier
    WHERE COALESCE(ft.counter_group, ft.identifier) = :counter_group
      AND f.specification_ref = :spec_id
      AND f.caption IS NOT NULL AND f.caption != ''
    ORDER BY f.file_seq
]]

-- Update float number
M.update_float_number = [[
    UPDATE spec_floats SET number = :number
    WHERE id = :id
]]

-- Build batch UPDATE for float numbers using CASE statement.
-- Assigns numbers to multiple floats in a single statement.
---@param ids_and_numbers table Array of {id=integer, number=integer} pairs
---@return string sql Executable UPDATE statement (no bind parameters — values are inlined)
function M.build_batch_float_number_update(ids_and_numbers)
    local case_parts = {}
    local id_list = {}
    for _, pair in ipairs(ids_and_numbers) do
        table.insert(case_parts, string.format("WHEN %d THEN %d", pair.id, pair.number))
        table.insert(id_list, tostring(pair.id))
    end
    return string.format([[
        UPDATE spec_floats SET number = CASE id %s END
        WHERE id IN (%s)
    ]], table.concat(case_parts, " "), table.concat(id_list, ","))
end

-- ============================================================================
-- Float Resolution
-- ============================================================================

-- Get all floats with type metadata for emit phase
M.select_all_floats_with_types = [[
    SELECT f.*, ft.caption_format, ft.counter_group
    FROM spec_floats f
    LEFT JOIN spec_float_types ft ON f.type_ref = ft.identifier
    ORDER BY f.rowid
]]

-- Check if a float type needs external rendering
M.select_float_type_external_render = [[
    SELECT needs_external_render FROM spec_float_types WHERE identifier = :id
]]

-- Get floats by type for a specification
M.select_floats_by_type = [[
    SELECT id, raw_content, raw_ast, pandoc_attributes, from_file, label, caption, file_seq, anchor, type_ref
    FROM spec_floats
    WHERE type_ref = :type_ref AND specification_ref = :spec_id
    ORDER BY file_seq
]]

-- Build SELECT for floats by multiple type references (dynamic IN clause).
---@param type_refs table Array of type references
---@return string sql SQL query string
---@return table params Parameter table with spec_id + type_N keys
function M.build_floats_by_types(type_refs)
    local placeholders = {}
    local params = {}
    for i, type_ref in ipairs(type_refs) do
        placeholders[i] = ":type_" .. i
        params["type_" .. i] = type_ref
    end
    local sql = string.format([[
        SELECT id, type_ref, raw_content, pandoc_attributes, from_file, label, caption, file_seq, anchor
        FROM spec_floats
        WHERE type_ref IN (%s) AND specification_ref = :spec_id
        ORDER BY file_seq
    ]], table.concat(placeholders, ", "))
    return sql, params
end

-- ============================================================================
-- External Rendering
-- ============================================================================

-- Get floats needing external render (resolved_ast is NULL)
M.select_floats_needing_external_render = [[
    SELECT f.id, f.raw_content, f.raw_ast, f.type_ref, f.pandoc_attributes
    FROM spec_floats f
    JOIN spec_float_types t ON f.type_ref = t.identifier
    WHERE t.needs_external_render = 1
      AND f.resolved_ast IS NULL
]]

-- Get views needing external render (resolved_ast is NULL)
M.select_views_needing_external_render = [[
    SELECT v.id, v.raw_ast, v.view_type_ref as type_ref
    FROM spec_views v
    JOIN spec_view_types t ON v.view_type_ref = t.identifier
    WHERE t.needs_external_render = 1
      AND v.resolved_ast IS NULL
]]

-- ============================================================================
-- Spec Object Rendering
-- ============================================================================

-- Get typed objects (non-composite) for render handler
M.select_typed_objects_by_spec = [[
    SELECT so.id, so.type_ref, so.specification_ref, so.ast,
           so.pid, so.title_text, so.level
    FROM spec_objects so
    JOIN spec_object_types sot ON so.type_ref = sot.identifier
    WHERE sot.is_composite = 0
      AND so.specification_ref = :spec_id
]]

-- Get composite objects with PIDs for heading ID patching
M.select_composite_objects_by_spec = [[
    SELECT so.id, so.pid, so.ast
    FROM spec_objects so
    JOIN spec_object_types sot ON so.type_ref = sot.identifier
    WHERE sot.is_composite = 1
      AND so.pid IS NOT NULL AND so.pid != ''
      AND so.ast IS NOT NULL
      AND so.specification_ref = :spec_id
]]

-- Get objects for XHTML conversion (ReqIF)
M.select_objects_for_xhtml = [[
    SELECT id, ast
    FROM spec_objects
    WHERE specification_ref = :spec_id
]]

-- Update object XHTML content (ReqIF cache)
M.update_object_xhtml = [[
    UPDATE spec_objects
    SET content_xhtml = :content_xhtml
    WHERE id = :id
]]

-- ============================================================================
-- Specifications
-- ============================================================================

-- Insert or replace a specification record
M.insert_specification = [[
    INSERT OR REPLACE INTO specifications (identifier, root_path, long_name, type_ref, pid, body_ast)
    VALUES (:identifier, :root_path, :long_name, :type_ref, :pid, :body_ast)
]]

-- ============================================================================
-- Specification Rendering
-- ============================================================================

-- Get specification for render handler
M.select_specification_for_render = [[
    SELECT identifier, root_path, long_name, type_ref, pid
    FROM specifications
    WHERE identifier = :spec_id
]]

-- Update specification header AST
M.update_specification_header_ast = [[
    UPDATE specifications
    SET header_ast = :header_ast
    WHERE identifier = :spec_id
]]

return M
