local M = {}

M.proof = {
    view = "view_object_bounds_violation",
    policy_key = "bounds_violation",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_bounds_violation AS
SELECT
  av.id,
  av.owner_object_id,
  av.name AS attribute_name,
  COALESCE(av.int_value, av.real_value) AS actual_value,
  ad.min_value,
  ad.max_value,
  so.from_file,
  so.start_line,
  so.title_text AS object_title
FROM spec_attribute_values av
JOIN spec_objects so ON av.owner_object_id = so.id
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
  AND ad.long_name = av.name
WHERE (av.int_value IS NOT NULL OR av.real_value IS NOT NULL)
  AND (
    (ad.min_value IS NOT NULL AND COALESCE(av.int_value, av.real_value) < ad.min_value) OR
    (ad.max_value IS NOT NULL AND COALESCE(av.int_value, av.real_value) > ad.max_value)
  );
]],
    message = function(row)
        return string.format("Value %s for attribute '%s' outside bounds [%s, %s]",
            row.actual_value, row.attribute_name,
            row.min_value or "-inf", row.max_value or "inf")
    end
}

return M
