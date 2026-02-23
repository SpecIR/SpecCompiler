local M = {}

M.proof = {
    view = "view_traceability_vc_missing_hlr",
    policy_key = "traceability_vc_to_hlr",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Verification case '%s' has no traceability link to an HLR",
            label
        )
    end
}

return M
