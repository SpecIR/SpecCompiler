local M = {}

M.proof = {
    view = "view_object_missing_required",
    policy_key = "missing_required",
    sql = [[
CREATE VIEW IF NOT EXISTS view_object_missing_required AS
SELECT
  so.id AS object_id,
  so.type_ref,
  so.title_text AS object_title,
  so.from_file,
  so.start_line,
  ad.long_name AS missing_attribute,
  ad.min_occurs
FROM spec_objects so
JOIN spec_attribute_types ad ON ad.owner_type_ref = so.type_ref
WHERE ad.min_occurs > 0
  AND NOT EXISTS (
    SELECT 1 FROM spec_attribute_values av
    WHERE av.owner_object_id = so.id
      AND av.name = ad.long_name
  );
]],
    message = function(row)
        return string.format("Object missing required attribute '%s' on %s",
            row.missing_attribute, row.object_title or row.object_id)
    end
}

return M
