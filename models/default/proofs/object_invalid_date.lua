local M = {}

M.proof = {
    view = "view_object_invalid_date",
    policy_key = "invalid_date",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_invalid_date AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.date_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
WHERE av.datatype = 'DATE'
  AND av.date_value IS NOT NULL
  AND av.date_value NOT GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]';
]],
    message = function(row)
        return string.format("Invalid date format for attribute '%s' (expected YYYY-MM-DD, got: '%s')",
            row.attribute_name, row.date_value or "nil")
    end
}

return M
