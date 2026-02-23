-- Test oracle for VC-VERIFY-003: Relation Violation Detection
-- Verifies relation errors are triggered for relation violations
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
        -- Note: missing_required may also appear due to VC objects missing required attrs
        -- float_duplicate_label: Triggered by same-parent duplicate floats (SEC-SAME-PARENT)
        -- unresolved_relation: Triggered by unresolved links (NONEXISTENT-ID, DOES-NOT-EXIST, fig:nonexistent-figure)
        -- ambiguous_relation: Triggered by ambiguous cross-scope reference (SEC-AMBIG-REF → fig:ambiguous-figure)
        local expected_codes = {
            ["unresolved_relation"] = "Unresolved link",
            ["float_duplicate_label"] = "Duplicate float label (same parent)",
            ["ambiguous_relation"] = "Ambiguous relation (cross-scope)"
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

        -- Report what was detected (for debugging)
        if #test_errors > 0 then
            local detected_list = {}
            for code, count in pairs(detected_codes) do
                table.insert(detected_list, string.format("%s (%d)", code, count))
            end
            table.sort(detected_list)

            return false, "Relation test failed:\n  Missing: " ..
                table.concat(test_errors, "\n  Missing: ") ..
                "\n  Detected: " .. table.concat(detected_list, ", ")
        end

        return true, nil
    end

    -- Standard mode (not used for this test)
    return false, "This test requires expect_errors mode"
end
