---Public API Views for SpecCompiler.
-- BI-friendly views for customers to build dashboards on specir.db.
-- These views provide a stable interface - internal table structure may change,
-- but these views maintain backward compatibility.
--
-- STABILITY GUARANTEE: Breaking changes require major version bump.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- PUBLIC API VIEWS
--
-- These views are the PUBLIC INTERFACE for BI tools and customer dashboards.
-- Customers can query these views with standard SQL tools (DBeaver, Metabase, etc.)
-- Views abstract internal schema complexity and provide stable column names.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- TRACEABILITY MATRIX
-- Shows all relations between objects with resolved references.
-- Answers: "Which requirements trace to which tests?"
--
-- Example queries:
--   SELECT * FROM public_traceability_matrix WHERE source_type = 'HLR'
--   SELECT * FROM public_traceability_matrix WHERE relation_type = 'verifies'
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_traceability_matrix AS
SELECT
  -- Source object info
  src.pid AS source_pid,
  src.type_ref AS source_type,
  src.title_text AS source_title,
  src.from_file AS source_file,

  -- Target object info
  tgt.pid AS target_pid,
  tgt.type_ref AS target_type,
  tgt.title_text AS target_title,
  tgt.from_file AS target_file,

  -- Relation info
  rt.identifier AS relation_type,
  rt.long_name AS relation_name,
  r.from_file AS link_file,

  -- IDs for joining to other tables
  r.id AS relation_id,
  r.source_object_id AS source_id,
  r.target_object_id AS target_id,
  r.specification_ref AS spec_id

FROM spec_relations r
JOIN spec_objects src ON r.source_object_id = src.id
JOIN spec_objects tgt ON r.target_object_id = tgt.id
LEFT JOIN spec_relation_types rt ON r.type_ref = rt.identifier
WHERE r.target_object_id IS NOT NULL;  -- Only resolved object-to-object relations

--------------------------------------------------------------------------------
-- COVERAGE REPORT
-- Shows traceability status of each object.
-- Answers: "Which requirements are orphans? Which have full coverage?"
--
-- Example queries:
--   SELECT * FROM public_coverage_report WHERE trace_status = 'orphan'
--   SELECT * FROM public_coverage_report WHERE incoming_traces = 0 AND type_ref = 'HLR'
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_coverage_report AS
SELECT
  so.pid,
  so.type_ref,
  so.title_text,
  so.from_file,
  so.start_line,

  -- Count outgoing traces (this object references others)
  COUNT(DISTINCT r_out.id) AS outgoing_traces,

  -- Count incoming traces (other objects reference this one)
  COUNT(DISTINCT r_in.id) AS incoming_traces,

  -- Classification
  CASE
    WHEN COUNT(r_out.id) > 0 AND COUNT(r_in.id) > 0 THEN 'fully_traced'
    WHEN COUNT(r_out.id) > 0 THEN 'traces_only'
    WHEN COUNT(r_in.id) > 0 THEN 'traced_by_only'
    ELSE 'orphan'
  END AS trace_status,

  -- IDs for joining
  so.id AS object_id,
  so.specification_ref AS spec_id

FROM spec_objects so
LEFT JOIN spec_relations r_out ON r_out.source_object_id = so.id
  AND (r_out.target_object_id IS NOT NULL OR r_out.target_float_id IS NOT NULL)
LEFT JOIN spec_relations r_in ON r_in.target_object_id = so.id
GROUP BY so.id;

--------------------------------------------------------------------------------
-- DANGLING REFERENCES
-- Shows unresolved relations (broken links).
-- Answers: "Which references couldn't be resolved?"
--
-- Example queries:
--   SELECT * FROM public_dangling_references
--   SELECT * FROM public_dangling_references WHERE from_file LIKE '%requirements%'
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_dangling_references AS
SELECT
  src.pid AS source_pid,
  src.type_ref AS source_type,
  src.title_text AS source_title,
  r.target_text AS target_reference,
  r.type_ref AS relation_type,
  r.from_file,
  src.start_line AS source_line,
  r.id AS relation_id,
  r.specification_ref AS spec_id
FROM spec_relations r
JOIN spec_objects src ON r.source_object_id = src.id
WHERE r.target_object_id IS NULL
  AND r.target_float_id IS NULL
  AND r.target_text IS NOT NULL;

--------------------------------------------------------------------------------
-- FLOAT INVENTORY
-- Lists all floats (figures, tables, charts) with their metadata.
-- Answers: "What figures exist? Where are they used?"
--
-- Example queries:
--   SELECT * FROM public_float_inventory WHERE float_type = 'PLANTUML'
--   SELECT * FROM public_float_inventory ORDER BY number
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_float_inventory AS
SELECT
  f.number,
  f.label,
  ft.long_name AS float_type,
  f.caption,
  f.from_file,
  f.anchor,
  po.pid AS parent_object_pid,
  po.title_text AS parent_object_title,
  f.id AS float_id,
  f.parent_object_id AS parent_id,
  f.specification_ref AS spec_id
FROM spec_floats f
LEFT JOIN spec_float_types ft ON f.type_ref = ft.identifier
LEFT JOIN spec_objects po ON f.parent_object_id = po.id;

--------------------------------------------------------------------------------
-- OBJECT SUMMARY
-- High-level summary of all objects by type.
-- Answers: "How many requirements do we have? How many tests?"
--
-- Example queries:
--   SELECT * FROM public_object_summary
--   SELECT * FROM public_object_summary WHERE object_count > 10
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_object_summary AS
SELECT
  sot.identifier AS type_code,
  sot.long_name AS type_name,
  COUNT(so.id) AS object_count,
  COUNT(DISTINCT so.from_file) AS file_count,
  MIN(so.pid) AS first_pid,
  MAX(so.pid) AS last_pid
FROM spec_object_types sot
LEFT JOIN spec_objects so ON so.type_ref = sot.identifier
GROUP BY sot.identifier
ORDER BY object_count DESC;

--------------------------------------------------------------------------------
-- SPECIFICATION LIST
-- Lists all specifications (documents) in the database.
-- Answers: "What documents are in this project?"
--
-- Example queries:
--   SELECT * FROM public_specification_list
--------------------------------------------------------------------------------
CREATE VIEW IF NOT EXISTS public_specification_list AS
SELECT
  s.pid,
  s.long_name AS title,
  sst.long_name AS spec_type,
  s.root_path AS file_path,
  (SELECT COUNT(*) FROM spec_objects so WHERE so.specification_ref = s.identifier) AS object_count,
  (SELECT COUNT(*) FROM spec_floats sf WHERE sf.specification_ref = s.identifier) AS float_count,
  (SELECT COUNT(*) FROM spec_relations sr WHERE sr.specification_ref = s.identifier) AS relation_count,
  s.identifier AS spec_id
FROM specifications s
LEFT JOIN spec_specification_types sst ON s.type_ref = sst.identifier;
]]

---Initialize public API views.
---@param db table DbHandler with :exec_sql method
function M.initialize(db)
    db:exec_sql(M.SQL)
end

return M
