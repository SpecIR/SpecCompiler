---Proof SQL views for the default model.
-- CREATE VIEW statements extracted from individual proof modules.
-- Keyed by view name (matches M.proof.view in each proof file).

local M = {}

-- ============================================================================
-- Float proofs
-- ============================================================================

M.view_float_duplicate_label = [[
CREATE VIEW IF NOT EXISTS view_float_duplicate_label AS
SELECT
  sf.id AS float_id,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line,
  sf.specification_ref,
  COUNT(*) AS duplicate_count
FROM spec_floats sf
WHERE sf.label IS NOT NULL
GROUP BY sf.specification_ref, sf.parent_object_id, sf.label
HAVING COUNT(*) > 1;
]]

M.view_float_invalid_type = [[
CREATE VIEW IF NOT EXISTS view_float_invalid_type AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line
FROM spec_floats sf
WHERE sf.type_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM spec_float_types ft
    WHERE ft.identifier = sf.type_ref
  );
]]

M.view_float_orphan = [[
CREATE VIEW IF NOT EXISTS view_float_orphan AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.caption,
  sf.from_file,
  sf.file_seq,
  sf.start_line
FROM spec_floats sf
WHERE sf.parent_object_id IS NULL
  AND EXISTS (
    SELECT 1 FROM spec_objects so
    WHERE so.specification_ref = sf.specification_ref
      AND so.from_file = sf.from_file
  );
]]

M.view_float_render_failure = [[
CREATE VIEW IF NOT EXISTS view_float_render_failure AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line,
  ft.needs_external_render
FROM spec_floats sf
JOIN spec_float_types ft ON ft.identifier = sf.type_ref
WHERE ft.needs_external_render = 1
  AND sf.resolved_ast IS NULL
  AND sf.raw_content IS NOT NULL;
]]

-- ============================================================================
-- Object proofs
-- ============================================================================

M.view_object_bounds_violation = [[
CREATE VIEW IF NOT EXISTS view_object_bounds_violation AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  COALESCE(av.int_value, av.real_value) AS actual_value,
  ad.min_value,
  ad.max_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
  AND ad.long_name = av.name
WHERE (av.int_value IS NOT NULL OR av.real_value IS NOT NULL)
  AND (
    (ad.min_value IS NOT NULL AND COALESCE(av.int_value, av.real_value) < ad.min_value) OR
    (ad.max_value IS NOT NULL AND COALESCE(av.int_value, av.real_value) > ad.max_value)
  );
]]

M.view_object_cardinality_over = [[
CREATE VIEW IF NOT EXISTS view_object_cardinality_over AS
SELECT
  so.id AS object_id,
  so.title_text AS object_title,
  so.from_file,
  so.start_line,
  av.name AS attribute_name,
  COUNT(*) AS actual_count,
  ad.max_occurs
FROM spec_objects so
JOIN spec_attribute_values av ON av.owner_object_id = so.id
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
  AND ad.long_name = av.name
WHERE ad.max_occurs IS NOT NULL
GROUP BY so.id, av.name
HAVING COUNT(*) > ad.max_occurs;
]]

M.view_object_cast_failures = [[
CREATE VIEW IF NOT EXISTS view_object_cast_failures AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.datatype,
  av.raw_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title,
  (SELECT GROUP_CONCAT(sub.key, ', ')
   FROM (SELECT key FROM enum_values
         WHERE datatype_ref = sat.datatype_ref
         ORDER BY sequence) sub
  ) AS valid_values
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
LEFT JOIN spec_attribute_types sat
  ON sat.owner_type_ref = so.type_ref AND sat.long_name = av.name
WHERE av.raw_value IS NOT NULL
  AND av.datatype NOT IN ('XHTML')
  AND (
    (av.datatype = 'STRING'  AND av.string_value IS NULL) OR
    (av.datatype = 'INTEGER' AND av.int_value IS NULL) OR
    (av.datatype = 'REAL'    AND av.real_value IS NULL) OR
    (av.datatype = 'BOOLEAN' AND av.bool_value IS NULL) OR
    (av.datatype = 'DATE'    AND av.date_value IS NULL) OR
    (av.datatype = 'ENUM'    AND av.enum_ref IS NULL)
  )
UNION ALL
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.datatype,
  av.raw_value,
  s.root_path AS from_file,
  1 AS start_line,
  COALESCE(s.long_name, s.identifier) AS object_title,
  NULL AS valid_values
FROM spec_attribute_values av
JOIN specifications s ON av.specification_ref = s.identifier
WHERE av.owner_object_id IS NULL
  AND av.owner_float_id IS NULL
  AND av.raw_value IS NOT NULL
  AND av.datatype NOT IN ('XHTML')
  AND (
    (av.datatype = 'STRING'  AND av.string_value IS NULL) OR
    (av.datatype = 'INTEGER' AND av.int_value IS NULL) OR
    (av.datatype = 'REAL'    AND av.real_value IS NULL) OR
    (av.datatype = 'BOOLEAN' AND av.bool_value IS NULL) OR
    (av.datatype = 'DATE'    AND av.date_value IS NULL) OR
    (av.datatype = 'ENUM'    AND av.enum_ref IS NULL)
  );
]]

M.view_object_duplicate_pid = [[
CREATE VIEW IF NOT EXISTS view_object_duplicate_pid AS
SELECT
  so.id AS object_id,
  so.pid,
  so.from_file,
  so.start_line,
  so.title_text,
  so.specification_ref
FROM spec_objects so
WHERE so.pid IS NOT NULL
  AND so.pid IN (
    SELECT pid FROM spec_objects
    WHERE pid IS NOT NULL
    GROUP BY pid HAVING COUNT(*) > 1
  );
]]

M.view_object_invalid_date = [[
CREATE VIEW IF NOT EXISTS view_object_invalid_date AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.date_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
WHERE av.datatype = 'DATE'
  AND av.date_value IS NOT NULL
  AND av.date_value NOT GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]';
]]

M.view_object_invalid_enum = [[
CREATE VIEW IF NOT EXISTS view_object_invalid_enum AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.raw_value,
  av.enum_ref,
  so.from_file,
  so.start_line,
  so.title_text AS object_title,
  (SELECT GROUP_CONCAT(sub.key, ', ')
   FROM (SELECT key FROM enum_values
         WHERE datatype_ref = sat.datatype_ref
         ORDER BY sequence) sub
  ) AS valid_values
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
LEFT JOIN spec_attribute_types sat
  ON sat.owner_type_ref = so.type_ref AND sat.long_name = av.name
WHERE av.datatype = 'ENUM'
  AND av.enum_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM enum_values ev
    WHERE ev.identifier = av.enum_ref
  );
]]

M.view_object_missing_required = [[
CREATE VIEW IF NOT EXISTS view_object_missing_required AS
SELECT
  so.id AS object_id,
  so.type_ref,
  so.title_text AS object_title,
  so.from_file,
  so.start_line,
  ad.long_name AS missing_attribute,
  ad.min_occurs
FROM spec_objects so
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
WHERE ad.min_occurs > 0
  AND NOT EXISTS (
    SELECT 1 FROM spec_attribute_values av
    WHERE av.owner_object_id = so.id
      AND av.name = ad.long_name
  );
]]

-- ============================================================================
-- Relation proofs
-- ============================================================================

M.view_relation_ambiguous = [[
CREATE VIEW IF NOT EXISTS view_relation_ambiguous AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE r.is_ambiguous = 1;
]]

M.view_relation_dangling = [[
CREATE VIEW IF NOT EXISTS view_relation_dangling AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.target_object_id,
  r.target_float_id,
  r.type_ref AS relation_type,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE (r.target_object_id IS NOT NULL OR r.target_float_id IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM spec_objects o WHERE o.id = r.target_object_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM spec_floats f WHERE f.id = r.target_float_id
  );
]]

M.view_relation_unresolved = [[
CREATE VIEW IF NOT EXISTS view_relation_unresolved AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE r.target_text IS NOT NULL
  AND r.target_object_id IS NULL AND r.target_float_id IS NULL
  -- Only flag relations whose selector maps to a resolvable base type.
  -- Base types (PID_REF, LABEL_REF) have extends IS NULL and are used as
  -- extends targets by child types. Their link_selector must match.
  AND EXISTS (
    SELECT 1 FROM spec_relation_types rt
    WHERE rt.extends IS NULL
      AND rt.identifier IN (
          SELECT DISTINCT extends FROM spec_relation_types WHERE extends IS NOT NULL
      )
      AND (rt.link_selector = r.link_selector
           OR (',' || rt.link_selector || ',') LIKE ('%,' || r.link_selector || ',%'))
  );
]]

-- ============================================================================
-- Specification proofs
-- ============================================================================

M.view_spec_invalid_type = [[
CREATE VIEW IF NOT EXISTS view_spec_invalid_type AS
SELECT
  s.identifier AS spec_id,
  s.type_ref,
  s.long_name AS spec_title,
  s.root_path AS from_file,
  1 AS start_line
FROM specifications s
WHERE s.type_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM spec_specification_types st
    WHERE st.identifier = s.type_ref
  );
]]

M.view_spec_missing_required = [[
CREATE VIEW IF NOT EXISTS view_spec_missing_required AS
SELECT
  s.identifier AS spec_id,
  s.type_ref,
  s.long_name AS spec_title,
  s.root_path AS from_file,
  1 AS start_line,
  ad.long_name AS missing_attribute,
  ad.min_occurs
FROM specifications s
JOIN spec_attribute_types ad ON ad.owner_type_ref = s.type_ref
WHERE ad.min_occurs > 0
  AND NOT EXISTS (
    SELECT 1 FROM spec_attribute_values av
    WHERE av.specification_ref = s.identifier
      AND av.owner_object_id IS NULL
      AND av.name = ad.long_name
  );
]]

-- ============================================================================
-- View proofs
-- ============================================================================

M.view_view_materialization_failure = [[
        CREATE VIEW IF NOT EXISTS view_view_materialization_failure AS
        SELECT
          sv.id AS view_id,
          sv.view_type_ref,
          sv.from_file,
          sv.file_seq,
          sv.start_line
        FROM spec_views sv
        JOIN spec_view_types vt ON vt.identifier = sv.view_type_ref
        WHERE vt.materializer_type IS NOT NULL
          AND sv.resolved_ast IS NULL
          AND sv.resolved_data IS NULL;
    ]]

return M
