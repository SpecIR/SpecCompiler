-- Test oracle for VC-VERIFY-002: Float Violation Detection
-- Verifies float_xxx errors are triggered for float violations
--
-- In expect_errors mode, this oracle verifies that the expected policy_key codes
-- were detected by the proof view system.

return function(actual_doc, helpers)
    -- In expect_errors mode, actual_doc is nil and we check diagnostics
    if helpers.expect_errors then
        local test_errors = {}
        local function err(msg) table.insert(test_errors, msg) end

        local diag = helpers.diagnostics
        if not diag then
            return false, "No diagnostics available"
        end

        -- Expected policy_key codes for this test
        local expected_codes = {
            ["float_orphan"] = "Orphan float warning",
            ["float_duplicate_label"] = "Duplicate float label",
            ["float_render_failure"] = "Float render failure",
        }

        -- Build a set of detected codes
        local detected_codes = {}
        for _, e in ipairs(diag.errors or {}) do
            if e.code then
                detected_codes[e.code] = (detected_codes[e.code] or 0) + 1
            end
        end
        for _, w in ipairs(diag.warnings or {}) do
            if w.code then
                detected_codes[w.code] = (detected_codes[w.code] or 0) + 1
            end
        end

        -- Verify expected codes were detected
        for code, desc in pairs(expected_codes) do
            if not detected_codes[code] then
                err(string.format("Expected %s (%s) but it was not detected", code, desc))
            end
        end

        -- Verify float_orphan count is exactly 1 (only the top-level orphan)
        if detected_codes["float_orphan"] and detected_codes["float_orphan"] ~= 1 then
            err(string.format(
                "Expected exactly 1 float_orphan diagnostic, got %d",
                detected_codes["float_orphan"]))
        end

        -- Verify from_file alignment via database query (confirms the SQL
        -- predicate so.from_file = sf.from_file matched correctly)
        if helpers.db_file then
            local ok, sqlite3 = pcall(require, "lsqlite3")
            if ok and sqlite3 then
                local db = sqlite3.open(helpers.db_file, sqlite3.OPEN_READONLY)
                if db then
                    local orphan_count = 0
                    for row in db:nrows("SELECT * FROM view_float_orphan") do
                        orphan_count = orphan_count + 1
                    end
                    db:close()

                    if orphan_count == 0 then
                        err("view_float_orphan returned 0 rows -- from_file alignment may be broken")
                    elseif orphan_count > 1 then
                        err(string.format(
                            "view_float_orphan returned %d rows, expected 1", orphan_count))
                    end
                end
            end
        end

        -- Report what was detected (for debugging)
        if #test_errors > 0 then
            local detected_list = {}
            for code, count in pairs(detected_codes) do
                table.insert(detected_list, string.format("%s (%d)", code, count))
            end
            table.sort(detected_list)

            return false, "Float test failed:\n  Missing: " ..
                table.concat(test_errors, "\n  Missing: ") ..
                "\n  Detected: " .. table.concat(detected_list, ", ")
        end

        return true, nil
    end

    -- Standard mode (not used for this test)
    return false, "This test requires expect_errors mode"
end
