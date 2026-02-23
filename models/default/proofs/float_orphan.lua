local M = {}

M.proof = {
    view = "view_float_orphan",
    policy_key = "float_orphan",
    sql = [[
CREATE VIEW IF NOT EXISTS view_float_orphan AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.caption,
  sf.from_file,
  sf.file_seq,
  sf.start_line
FROM spec_floats sf
WHERE sf.parent_object_id IS NULL
  AND EXISTS (
    SELECT 1 FROM spec_objects so
    WHERE so.specification_ref = sf.specification_ref
      AND so.from_file = sf.from_file
  );
]],
    message = function(row)
        return string.format("Float '%s' has no parent object", row.label or row.float_id)
    end
}

return M
