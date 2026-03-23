---Proof SQL views for the sw_docs model.
-- CREATE VIEW statements extracted from individual proof modules.
-- Keyed by view name (matches M.proof.view in each proof file).

local M = {}

-- ============================================================================
-- Traceability proofs
-- ============================================================================

M.view_traceability_csc_missing_fd = [[
CREATE VIEW IF NOT EXISTS view_traceability_csc_missing_fd AS
SELECT
  csc.id AS object_id,
  csc.pid AS object_pid,
  csc.title_text AS object_title,
  csc.from_file,
  csc.start_line
FROM spec_objects csc
WHERE csc.type_ref = 'CSC'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects fd ON fd.id = r.source_object_id
    WHERE r.target_object_id = csc.id
      AND fd.type_ref = 'FD'
  );
]]

M.view_traceability_csu_missing_fd = [[
CREATE VIEW IF NOT EXISTS view_traceability_csu_missing_fd AS
SELECT
  csu.id AS object_id,
  csu.pid AS object_pid,
  csu.title_text AS object_title,
  csu.from_file,
  csu.start_line
FROM spec_objects csu
WHERE csu.type_ref = 'CSU'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects fd ON fd.id = r.source_object_id
    WHERE r.target_object_id = csu.id
      AND fd.type_ref = 'FD'
  );
]]

M.view_traceability_fd_missing_csc = [[
CREATE VIEW IF NOT EXISTS view_traceability_fd_missing_csc AS
SELECT
  fd.id AS object_id,
  fd.pid AS object_pid,
  fd.title_text AS object_title,
  fd.from_file,
  fd.start_line
FROM spec_objects fd
WHERE fd.type_ref = 'FD'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects target ON target.id = r.target_object_id
    WHERE r.source_object_id = fd.id
      AND target.type_ref = 'CSC'
  );
]]

M.view_traceability_fd_missing_csu = [[
CREATE VIEW IF NOT EXISTS view_traceability_fd_missing_csu AS
SELECT
  fd.id AS object_id,
  fd.pid AS object_pid,
  fd.title_text AS object_title,
  fd.from_file,
  fd.start_line
FROM spec_objects fd
WHERE fd.type_ref = 'FD'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects target ON target.id = r.target_object_id
    WHERE r.source_object_id = fd.id
      AND target.type_ref = 'CSU'
  );
]]

M.view_traceability_hlr_missing_vc = [[
CREATE VIEW IF NOT EXISTS view_traceability_hlr_missing_vc AS
SELECT
  hlr.id AS object_id,
  hlr.pid AS object_pid,
  hlr.title_text AS object_title,
  hlr.from_file,
  hlr.start_line
FROM spec_objects hlr
WHERE hlr.type_ref = 'HLR'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    WHERE r.target_object_id = hlr.id
      AND r.type_ref = 'VERIFIES'
  );
]]

M.view_traceability_llr_missing_vc = [[
CREATE VIEW IF NOT EXISTS view_traceability_llr_missing_vc AS
SELECT
  llr.id AS object_id,
  llr.pid AS object_pid,
  llr.title_text AS object_title,
  llr.from_file,
  llr.start_line
FROM spec_objects llr
WHERE llr.type_ref = 'LLR'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    WHERE r.target_object_id = llr.id
      AND r.type_ref = 'VERIFIES'
  );
]]

M.view_traceability_tr_missing_vc = [[
CREATE VIEW IF NOT EXISTS view_traceability_tr_missing_vc AS
SELECT
  tr.id AS object_id,
  tr.pid AS object_pid,
  tr.title_text AS object_title,
  tr.from_file,
  tr.start_line
FROM spec_objects tr
WHERE tr.type_ref = 'TR'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    JOIN spec_objects target ON target.id = r.target_object_id
    WHERE r.source_object_id = tr.id
      AND target.type_ref = 'VC'
  );
]]

M.view_traceability_vc_missing_hlr = [[
CREATE VIEW IF NOT EXISTS view_traceability_vc_missing_hlr AS
SELECT
  vc.id AS object_id,
  vc.pid AS object_pid,
  vc.title_text AS object_title,
  vc.from_file,
  vc.start_line
FROM spec_objects vc
WHERE vc.type_ref = 'VC'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r
    WHERE r.source_object_id = vc.id
      AND r.type_ref = 'VERIFIES'
  );
]]

-- ============================================================================
-- Allocation traceability proofs
-- ============================================================================

M.view_traceability_hlr_missing_allocation = [[
CREATE VIEW IF NOT EXISTS view_traceability_hlr_missing_allocation AS
SELECT
  hlr.id AS object_id,
  hlr.pid AS object_pid,
  hlr.title_text AS object_title,
  hlr.from_file,
  hlr.start_line
FROM spec_objects hlr
WHERE hlr.type_ref = 'HLR'
  AND NOT EXISTS (
    SELECT 1
    FROM spec_relations r_belongs
    JOIN spec_objects sf ON sf.id = r_belongs.target_object_id
      AND sf.type_ref = 'SF'
    JOIN spec_relations r_realizes ON r_realizes.target_object_id = sf.id
      AND r_realizes.type_ref = 'REALIZES'
    JOIN spec_objects fd ON fd.id = r_realizes.source_object_id
      AND fd.type_ref = 'FD'
    JOIN spec_relations r_fd_csc ON r_fd_csc.source_object_id = fd.id
    JOIN spec_objects csc ON csc.id = r_fd_csc.target_object_id
      AND csc.type_ref = 'CSC'
    WHERE r_belongs.source_object_id = hlr.id
      AND r_belongs.type_ref = 'BELONGS'
  );
]]

return M
