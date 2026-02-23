local M = {}

M.proof = {
    view = "view_traceability_llr_missing_vc",
    policy_key = "traceability_llr_to_vc",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Low-level requirement '%s' is not covered by any VC",
            label
        )
    end
}

return M
