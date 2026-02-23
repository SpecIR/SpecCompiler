local M = {}

M.proof = {
    view = "view_traceability_csu_missing_fd",
    policy_key = "traceability_csu_to_fd",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "CSU '%s' has no functional description (FD) allocated to it",
            label
        )
    end
}

return M
