local M = {}

M.proof = {
    view = "view_traceability_csc_missing_fd",
    policy_key = "traceability_csc_to_fd",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "CSC '%s' has no functional description (FD) allocated to it",
            label
        )
    end
}

return M
