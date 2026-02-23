local M = {}

M.proof = {
    view = "view_view_materialization_failure",
    policy_key = "view_materialization_failure",

    sql = [[
        CREATE VIEW IF NOT EXISTS view_view_materialization_failure AS
        SELECT
          sv.id AS view_id,
          sv.view_type_ref,
          sv.from_file,
          sv.file_seq,
          sv.start_line
        FROM spec_views sv
        JOIN spec_view_types vt ON vt.identifier = sv.view_type_ref
        WHERE vt.materializer_type IS NOT NULL
          AND sv.resolved_ast IS NULL
          AND sv.resolved_data IS NULL;
    ]],

    message = function(row)
        return string.format("View '%s' materialization failed",
            row.view_type_ref or row.view_id)
    end,
}

return M
