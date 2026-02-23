local M = {}

M.proof = {
    view = "view_relation_unresolved",
    policy_key = "unresolved_relation",
    sql = [[
CREATE VIEW IF NOT EXISTS view_relation_unresolved AS
SELECT
  r.id,
  r.source_object_id,
  r.target_text,
  r.from_file,
  COALESCE(so.title_text, '(unknown source)') AS source_title,
  CASE WHEN r.link_line > 0 THEN r.link_line ELSE COALESCE(so.start_line, 0) END AS start_line
FROM spec_relations r
LEFT JOIN spec_objects so ON r.source_object_id = so.id
WHERE r.target_text IS NOT NULL
  AND r.target_object_id IS NULL AND r.target_float_id IS NULL
  -- Only flag relations whose selector maps to a resolvable base type.
  -- Base types (PID_REF, LABEL_REF) have extends IS NULL and are used as
  -- extends targets by child types. Their link_selector must match.
  AND EXISTS (
    SELECT 1 FROM spec_relation_types rt
    WHERE rt.extends IS NULL
      AND rt.identifier IN (
          SELECT DISTINCT extends FROM spec_relation_types WHERE extends IS NOT NULL
      )
      AND (rt.link_selector = r.link_selector
           OR (',' || rt.link_selector || ',') LIKE ('%,' || r.link_selector || ',%'))
  );
]],
    message = function(row)
        return string.format("Unresolved link: '%s' (no matching object found)", row.target_text)
    end
}

return M
