local M = {}

M.proof = {
    view = "view_spec_missing_required",
    policy_key = "spec_missing_required",
    sql = [[
CREATE VIEW IF NOT EXISTS view_spec_missing_required AS
SELECT
  s.identifier AS spec_id,
  s.type_ref,
  s.long_name AS spec_title,
  s.root_path AS from_file,
  1 AS start_line,
  ad.long_name AS missing_attribute,
  ad.min_occurs
FROM specifications s
JOIN spec_attribute_types ad ON ad.owner_type_ref = s.type_ref
WHERE ad.min_occurs > 0
  AND NOT EXISTS (
    SELECT 1 FROM spec_attribute_values av
    WHERE av.specification_ref = s.identifier
      AND av.owner_object_id IS NULL
      AND av.name = ad.long_name
  );
]],
    message = function(row)
        return string.format("Specification missing required attribute '%s'",
            row.missing_attribute)
    end
}

return M
