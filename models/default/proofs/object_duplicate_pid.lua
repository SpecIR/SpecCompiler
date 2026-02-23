local M = {}

M.proof = {
    view = "view_object_duplicate_pid",
    policy_key = "object_duplicate_pid",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_duplicate_pid AS
SELECT
  so.id AS object_id,
  so.pid,
  so.from_file,
  so.start_line,
  so.title_text,
  so.specification_ref
FROM spec_objects so
WHERE so.pid IS NOT NULL
  AND so.pid IN (
    SELECT pid FROM spec_objects
    WHERE pid IS NOT NULL
    GROUP BY pid HAVING COUNT(*) > 1
  );
]],
    message = function(row)
        return string.format("Duplicate PID '%s' on object '%s' in '%s'",
            row.pid, row.title_text or tostring(row.object_id), row.specification_ref or "unknown")
    end
}

return M
