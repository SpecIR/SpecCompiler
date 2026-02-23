local M = {}

M.proof = {
    view = "view_traceability_tr_missing_vc",
    policy_key = "traceability_tr_to_vc",
    sql = [[
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
]],
    message = function(row)
        local label = row.object_pid or row.object_title or row.object_id
        return string.format(
            "Test result '%s' has no traceability link to a VC",
            label
        )
    end
}

return M
