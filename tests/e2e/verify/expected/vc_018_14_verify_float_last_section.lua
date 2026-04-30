-- Test oracle for VC-018-14: Floats in every section must have parent assigned.
-- Verifies that floats are NOT orphaned, especially:
-- - Float as the very last element in the document (EOF)
-- - Float in the last section before another section
-- - Float in a middle section
-- This catches bugs where end_line is too small, causing orphans.

return function(actual_doc, helpers)
    if helpers.expect_errors then
        local test_errors = {}
        local debug_info = {}
        local function err(msg) table.insert(test_errors, msg) end

        local diag = helpers.diagnostics
        if not diag then
            return false, "No diagnostics available"
        end

        -- Check that NO float_orphan diagnostic was emitted
        local orphan_count = 0
        for _, e in ipairs(diag.errors or {}) do
            if e.code == "float_orphan" then
                orphan_count = orphan_count + 1
            end
        end
        for _, w in ipairs(diag.warnings or {}) do
            if w.code == "float_orphan" then
                orphan_count = orphan_count + 1
            end
        end

        if orphan_count > 0 then
            err(string.format(
                "Float in last section was incorrectly flagged as orphan (%d orphan diagnostic(s) found)",
                orphan_count))
        end

        -- Verify via database: the float should have parent_object_id set
        if helpers.db_file then
            local ok, sqlite3 = pcall(require, "lsqlite3")
            if ok and sqlite3 then
                local db = sqlite3.open(helpers.db_file, sqlite3.OPEN_READONLY)
                if db then
                    -- Dump object end_lines for debugging
                    for row in db:nrows([[
                        SELECT id, pid, start_line, end_line, level
                        FROM spec_objects ORDER BY file_seq
                    ]]) do
                        table.insert(debug_info, string.format(
                            "obj id=%d pid=%s start=%s end=%s level=%d",
                            row.id, row.pid or "NULL",
                            tostring(row.start_line), tostring(row.end_line),
                            row.level))
                    end

                    -- Check ALL floats have parents
                    for row in db:nrows([[
                        SELECT sf.id, sf.syntax_key, sf.start_line, sf.parent_object_id
                        FROM spec_floats sf
                    ]]) do
                        table.insert(debug_info, string.format(
                            "float id=%d key=%s start=%s parent=%s",
                            row.id, row.syntax_key or "NULL",
                            tostring(row.start_line),
                            tostring(row.parent_object_id)))
                        if not row.parent_object_id then
                            err(string.format(
                                "Float '%s' (id=%d, line=%s) has NULL parent_object_id",
                                row.syntax_key or "?", row.id,
                                tostring(row.start_line)))
                        end
                    end

                    -- Also check view_float_orphan has no rows for this file
                    local view_orphan_count = 0
                    for _ in db:nrows("SELECT * FROM view_float_orphan") do
                        view_orphan_count = view_orphan_count + 1
                    end
                    if view_orphan_count > 0 then
                        err(string.format(
                            "view_float_orphan returned %d rows, expected 0",
                            view_orphan_count))
                    end

                    db:close()
                end
            end
        end

        if #test_errors > 0 then
            return false, "Float last-section parent test failed:\n  - " ..
                table.concat(test_errors, "\n  - ") ..
                "\n  DB state: " .. table.concat(debug_info, "; ")
        end

        return true, nil
    end

    return false, "This test requires expect_errors mode"
end
