local M = {}

M.proof = {
    view = "view_float_invalid_type",
    policy_key = "float_invalid_type",
    sql = [[
CREATE VIEW IF NOT EXISTS view_float_invalid_type AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line
FROM spec_floats sf
WHERE sf.type_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM spec_float_types ft
    WHERE ft.identifier = sf.type_ref
  );
]],
    message = function(row)
        return string.format("Float '%s' has invalid type '%s'", row.label or row.float_id, row.type_ref or "nil")
    end
}

return M
