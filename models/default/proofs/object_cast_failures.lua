local M = {}

M.proof = {
    view = "view_object_cast_failures",
    policy_key = "invalid_cast",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_cast_failures AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.datatype,
  av.raw_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title,
  (SELECT GROUP_CONCAT(sub.key, ', ')
   FROM (SELECT key FROM enum_values
         WHERE datatype_ref = sat.datatype_ref
         ORDER BY sequence) sub
  ) AS valid_values
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
LEFT JOIN spec_attribute_types sat
  ON sat.owner_type_ref = so.type_ref AND sat.long_name = av.name
WHERE av.raw_value IS NOT NULL
  AND av.datatype NOT IN ('XHTML')
  AND (
    (av.datatype = 'STRING'  AND av.string_value IS NULL) OR
    (av.datatype = 'INTEGER' AND av.int_value IS NULL) OR
    (av.datatype = 'REAL'    AND av.real_value IS NULL) OR
    (av.datatype = 'BOOLEAN' AND av.bool_value IS NULL) OR
    (av.datatype = 'DATE'    AND av.date_value IS NULL) OR
    (av.datatype = 'ENUM'    AND av.enum_ref IS NULL)
  )
UNION ALL
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.datatype,
  av.raw_value,
  s.root_path AS from_file,
  1 AS start_line,
  COALESCE(s.long_name, s.identifier) AS object_title,
  NULL AS valid_values
FROM spec_attribute_values av
JOIN specifications s ON av.specification_ref = s.identifier
WHERE av.owner_object_id IS NULL
  AND av.owner_float_id IS NULL
  AND av.raw_value IS NOT NULL
  AND av.datatype NOT IN ('XHTML')
  AND (
    (av.datatype = 'STRING'  AND av.string_value IS NULL) OR
    (av.datatype = 'INTEGER' AND av.int_value IS NULL) OR
    (av.datatype = 'REAL'    AND av.real_value IS NULL) OR
    (av.datatype = 'BOOLEAN' AND av.bool_value IS NULL) OR
    (av.datatype = 'DATE'    AND av.date_value IS NULL) OR
    (av.datatype = 'ENUM'    AND av.enum_ref IS NULL)
  );
]],
    message = function(row)
        local msg = string.format("Failed to cast attribute '%s' to %s (value: '%s')",
            row.attribute_name, row.datatype, row.raw_value or "nil")
        if row.valid_values and row.valid_values ~= "" then
            msg = msg .. "; valid values: " .. row.valid_values
        end
        return msg
    end
}

return M
