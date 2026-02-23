---Full-text search queries for SpecCompiler.
-- INSERT/DELETE/SELECT operations for FTS tables:
-- fts_objects, fts_attributes, fts_floats.

local M = {}

-- ============================================================================
-- Clear FTS Data
-- ============================================================================

M.clear_fts_objects = [[
    DELETE FROM fts_objects WHERE spec_id = :spec_id
]]

M.clear_fts_attributes = [[
    DELETE FROM fts_attributes WHERE spec_id = :spec_id
]]

M.clear_fts_floats = [[
    DELETE FROM fts_floats WHERE spec_id = :spec_id
]]

-- ============================================================================
-- Index Queries (for populating FTS)
-- ============================================================================

M.get_objects_for_fts = [[
    SELECT
        o.id,
        o.label,
        o.pid,
        o.type_ref as object_type,
        o.specification_ref as spec_id,
        o.title_text as title,
        o.ast
    FROM spec_objects o
    WHERE o.specification_ref = :spec_id
]]

M.get_float_raw_content = [[
    SELECT raw_content FROM spec_floats
    WHERE parent_object_id = :obj_id
      AND raw_content IS NOT NULL
]]

M.get_attributes_for_fts = [[
    SELECT
        a.owner_object_id,
        a.name as attr_name,
        a.datatype as attr_type,
        COALESCE(a.string_value, a.raw_value, '') as attr_value,
        a.ast
    FROM spec_attribute_values a
    WHERE a.specification_ref = :spec_id
]]

M.get_floats_for_fts = [[
    SELECT
        f.id,
        f.label,
        f.type_ref as float_type,
        f.parent_object_id as parent_ref,
        f.caption,
        f.raw_content as raw_source
    FROM spec_floats f
    WHERE f.specification_ref = :spec_id
]]

-- ============================================================================
-- Insert FTS Data
-- ============================================================================

M.insert_fts_object = [[
    INSERT INTO fts_objects (identifier, object_type, spec_id, title, content, raw_source)
    VALUES (:identifier, :object_type, :spec_id, :title, :content, :raw_source)
]]

M.insert_fts_attribute = [[
    INSERT INTO fts_attributes (owner_ref, spec_id, attr_name, attr_type, attr_value)
    VALUES (:owner_ref, :spec_id, :attr_name, :attr_type, :attr_value)
]]

M.insert_fts_float = [[
    INSERT INTO fts_floats (identifier, float_type, spec_id, parent_ref, caption, raw_source)
    VALUES (:identifier, :float_type, :spec_id, :parent_ref, :caption, :raw_source)
]]

-- ============================================================================
-- FTS Presence Checks (for cached builds)
-- ============================================================================

-- Count spec objects for FTS up-to-date check
M.count_objects_by_spec = [[
    SELECT COUNT(*) AS c FROM spec_objects WHERE specification_ref = :spec_id
]]

-- Count FTS object entries for FTS up-to-date check
M.count_fts_objects_by_spec = [[
    SELECT COUNT(*) AS c FROM fts_objects WHERE spec_id = :spec_id
]]

-- Count spec floats for FTS up-to-date check
M.count_floats_by_spec = [[
    SELECT COUNT(*) AS c FROM spec_floats WHERE specification_ref = :spec_id
]]

-- Count FTS float entries for FTS up-to-date check
M.count_fts_floats_by_spec = [[
    SELECT COUNT(*) AS c FROM fts_floats WHERE spec_id = :spec_id
]]

-- ============================================================================
-- FTS Float Content Pre-fetch
-- ============================================================================

-- Get float raw content grouped by parent object (for FTS indexing)
M.float_raw_content_by_spec = [[
    SELECT parent_object_id, raw_content
    FROM spec_floats
    WHERE specification_ref = :spec_id
      AND raw_content IS NOT NULL
      AND raw_content != ''
]]

return M
