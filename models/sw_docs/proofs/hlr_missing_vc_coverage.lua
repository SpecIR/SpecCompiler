local M = {}

M.proof = {
    view = "view_traceability_hlr_missing_vc",
    policy_key = "traceability_hlr_to_vc",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "High-level requirement '%s' is not covered by any VC",
            label
        )
    end
}

return M
