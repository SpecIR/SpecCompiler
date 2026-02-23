local M = {}

M.proof = {
    view = "view_spec_invalid_type",
    policy_key = "spec_invalid_type",
    sql = [[
CREATE VIEW IF NOT EXISTS view_spec_invalid_type AS
SELECT
  s.identifier AS spec_id,
  s.type_ref,
  s.long_name AS spec_title,
  s.root_path AS from_file,
  1 AS start_line
FROM specifications s
WHERE s.type_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM spec_specification_types st
    WHERE st.identifier = s.type_ref
  );
]],
    message = function(row)
        return string.format("Invalid specification type '%s'",
            row.type_ref or "nil")
    end
}

return M
