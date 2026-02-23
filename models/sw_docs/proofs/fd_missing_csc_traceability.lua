local M = {}

M.proof = {
    view = "view_traceability_fd_missing_csc",
    policy_key = "traceability_fd_to_csc",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Functional description '%s' has no traceability link to a CSC",
            label
        )
    end
}

return M
