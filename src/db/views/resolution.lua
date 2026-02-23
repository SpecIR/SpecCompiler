---Resolution Views for SpecCompiler.
-- Internal views for resolving references, types, and relations.
-- Used by handlers to simplify resolution logic (moving code to SQL).
--
-- INTERNAL: These views may change between versions.
-- Use public_api.lua views for stable BI queries.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- RESOLUTION VIEWS (INTERNAL)
--
-- These views move resolution logic from handler Lua code into SQL.
-- This makes handlers thinner and exposes the SQL for debugging/optimization.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- FLOAT TYPE RESOLUTION
-- Resolves float type aliases to canonical identifiers.
-- E.g., "fig" -> "FIGURE", "puml" -> "PLANTUML"
--
-- Used by: spec_floats handler, spec_relations handler
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_float_type_resolution AS
SELECT
  f.id AS float_id,
  f.type_ref AS requested_type,
  COALESCE(ft.identifier, UPPER(f.type_ref)) AS resolved_type,
  ft.counter_group,
  ft.caption_format,
  ft.needs_external_render
FROM spec_floats f
LEFT JOIN spec_float_types ft ON
  UPPER(f.type_ref) = ft.identifier
  OR (ft.aliases IS NOT NULL AND ft.aliases LIKE '%,' || LOWER(f.type_ref) || ',%');

--------------------------------------------------------------------------------
-- RELATION TYPE RESOLUTION
-- Resolves relation type aliases to canonical identifiers.
-- E.g., "cite" -> "CITES", "ref" -> "REFERENCES"
--
-- Used by: spec_relations handler
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_relation_type_resolution AS
SELECT
  rt.identifier AS relation_type,
  rt.long_name,
  rt.link_selector,
  rt.is_default,
  rt.source_type_ref,
  rt.target_type_ref
FROM spec_relation_types rt;

--------------------------------------------------------------------------------
-- RESOLVED RELATIONS
-- Pre-resolves relation targets using scoped and global lookups.
-- Priority: 1) Float in same parent object, 2) Global float, 3) Object by PID
--
-- Used by: relation_analyzer handler (type-driven resolution)
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_resolved_relations AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.type_ref,
  r.from_file,
  -- Float resolution: scoped float > global float
  COALESCE(
    -- Priority 1: Float with matching label in same parent object (scoped)
    (SELECT f.id
     FROM spec_floats f
     WHERE f.label = r.target_text
       AND f.parent_object_id = r.source_object_id
     LIMIT 1),
    -- Priority 2: Float with matching label anywhere (global)
    (SELECT f.id
     FROM spec_floats f
     WHERE f.label = r.target_text
     LIMIT 1)
  ) AS resolved_target_float_id,
  -- Object resolution by PID
  (SELECT o.id
   FROM spec_objects o
   WHERE o.pid = r.target_text
   LIMIT 1) AS resolved_target_object_id
FROM spec_relations r
WHERE r.target_object_id IS NULL
  AND r.target_float_id IS NULL
  AND r.target_text IS NOT NULL;

--------------------------------------------------------------------------------
-- FLOAT ANCHORS
-- Computes scoped anchors for floats based on parent object PID.
-- Format: {parent_pid}-{type_prefix}-{label} or {type_prefix}-{label}
--
-- Used by: spec_floats handler (bulk UPDATE from this view)
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_float_anchors AS
SELECT
  f.id AS float_id,
  f.label,
  f.type_ref,
  po.pid AS parent_pid,
  CASE
    WHEN po.pid IS NOT NULL THEN
      LOWER(po.pid) || '-' || LOWER(SUBSTR(f.type_ref, 1, 3)) || '-' || f.label
    ELSE
      LOWER(SUBSTR(f.type_ref, 1, 3)) || '-' || f.label
  END AS computed_anchor
FROM spec_floats f
LEFT JOIN spec_objects po ON f.parent_object_id = po.id
WHERE f.anchor IS NULL;

--------------------------------------------------------------------------------
-- FLOAT NUMBERING
-- Pre-computes float numbers within counter groups.
-- Floats sharing counter_group are numbered sequentially.
--
-- Used by: float_numbering handler
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_float_numbering AS
SELECT
  f.id AS float_id,
  f.specification_ref,
  f.type_ref,
  COALESCE(ft.counter_group, f.type_ref) AS counter_group,
  f.file_seq,
  ROW_NUMBER() OVER (
    PARTITION BY f.specification_ref, COALESCE(ft.counter_group, f.type_ref)
    ORDER BY f.file_seq
  ) AS computed_number
FROM spec_floats f
LEFT JOIN spec_float_types ft ON f.type_ref = ft.identifier;

--------------------------------------------------------------------------------
-- OBJECT TYPE INFERENCE
-- Resolves implicit type aliases from header titles.
-- E.g., "## Introduction" -> SECTION type
--
-- Used by: spec_objects handler
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_object_type_inference AS
SELECT
  ita.alias AS title_pattern,
  ita.object_type_id AS inferred_type,
  sot.long_name AS type_name
FROM implicit_type_aliases ita
JOIN spec_object_types sot ON ita.object_type_id = sot.identifier;

--------------------------------------------------------------------------------
-- ATTRIBUTE TYPE RESOLUTION
-- Resolves attribute datatypes for validation.
-- Links attribute values to their expected types.
--
-- Used by: attribute_caster handler, proof views
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS view_attribute_type_resolution AS
SELECT
  av.id AS value_id,
  av.owner_object_id,
  av.name AS attr_name,
  av.raw_value,
  av.datatype AS declared_type,
  ad.identifier AS definition_id,
  dd.type AS expected_type,
  ad.min_value,
  ad.max_value,
  ad.min_occurs,
  ad.max_occurs
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
LEFT JOIN spec_attribute_types ad ON
  ad.owner_type_ref = so.type_ref
  AND ad.long_name = av.name
LEFT JOIN datatype_definitions dd ON ad.datatype_ref = dd.identifier;
]]

---Initialize resolution views.
---@param db table DbHandler with :exec_sql method
function M.initialize(db)
    db:exec_sql(M.SQL)
end

return M
