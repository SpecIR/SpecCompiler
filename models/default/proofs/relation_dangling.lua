local M = {}

M.proof = {
    view = "view_relation_dangling",
    policy_key = "dangling_relation",
    sql = [[
CREATE VIEW IF NOT EXISTS view_relation_dangling AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.target_object_id,
  r.target_float_id,
  r.type_ref AS relation_type,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE (r.target_object_id IS NOT NULL OR r.target_float_id IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM spec_objects o WHERE o.id = r.target_object_id
  )
  AND NOT EXISTS (
    SELECT 1 FROM spec_floats f WHERE f.id = r.target_float_id
  );
]],
    message = function(row)
        return string.format("Dangling relation: target '%s' points to non-existent object", row.target_object_id or row.target_float_id)
    end
}

return M
