local M = {}

M.proof = {
    view = "view_float_render_failure",
    policy_key = "float_render_failure",
    sql = [[
CREATE VIEW IF NOT EXISTS view_float_render_failure AS
SELECT
  sf.id AS float_id,
  sf.type_ref,
  sf.label,
  sf.from_file,
  sf.file_seq,
  sf.start_line,
  ft.needs_external_render
FROM spec_floats sf
JOIN spec_float_types ft ON ft.identifier = sf.type_ref
WHERE ft.needs_external_render = 1
  AND sf.resolved_ast IS NULL
  AND sf.raw_content IS NOT NULL;
]],
    message = function(row)
        return string.format("Float '%s' external render failed", row.label or row.float_id)
    end
}

return M
