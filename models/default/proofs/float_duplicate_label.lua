local M = {}

M.proof = {
    view = "view_float_duplicate_label",
    policy_key = "float_duplicate_label",
    sql = [[
CREATE VIEW IF NOT EXISTS view_float_duplicate_label AS
SELECT
  sf.id AS float_id,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line,
  sf.specification_ref,
  COUNT(*) AS duplicate_count
FROM spec_floats sf
WHERE sf.label IS NOT NULL
GROUP BY sf.specification_ref, sf.parent_object_id, sf.label
HAVING COUNT(*) > 1;
]],
    message = function(row)
        return string.format("Duplicate float label '%s' in specification (found %d)", row.label, row.duplicate_count)
    end
}

return M
