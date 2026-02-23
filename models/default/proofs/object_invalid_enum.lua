local M = {}

M.proof = {
    view = "view_object_invalid_enum",
    policy_key = "invalid_enum",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_invalid_enum AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  av.raw_value,
  av.enum_ref,
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
WHERE av.datatype = 'ENUM'
  AND av.enum_ref IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM enum_values ev
    WHERE ev.identifier = av.enum_ref
  );
]],
    message = function(row)
        local msg = string.format("Invalid enum value for attribute '%s' (value: '%s')",
            row.attribute_name, row.raw_value or "nil")
        if row.valid_values and row.valid_values ~= "" then
            msg = msg .. "; valid values: " .. row.valid_values
        end
        return msg
    end
}

return M
