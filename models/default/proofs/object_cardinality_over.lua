local M = {}

M.proof = {
    view = "view_object_cardinality_over",
    policy_key = "cardinality_over",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_cardinality_over AS
SELECT
  so.id AS object_id,
  so.title_text AS object_title,
  so.from_file,
  so.start_line,
  av.name AS attribute_name,
  COUNT(*) AS actual_count,
  ad.max_occurs
FROM spec_objects so
JOIN spec_attribute_values av ON av.owner_object_id = so.id
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
  AND ad.long_name = av.name
WHERE ad.max_occurs IS NOT NULL
GROUP BY so.id, av.name
HAVING COUNT(*) > ad.max_occurs;
]],
    message = function(row)
        return string.format("Object attribute '%s' has %d values, max allowed is %d",
            row.attribute_name, row.actual_count, row.max_occurs)
    end
}

return M
