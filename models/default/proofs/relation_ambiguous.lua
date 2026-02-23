local M = {}

M.proof = {
    view = "view_relation_ambiguous",
    policy_key = "ambiguous_relation",
    sql = [[
CREATE VIEW IF NOT EXISTS view_relation_ambiguous AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE r.is_ambiguous = 1;
]],
    message = function(row)
        return string.format("Ambiguous relation '%s' — multiple targets or inference rules matched", row.target_text)
    end
}

return M
