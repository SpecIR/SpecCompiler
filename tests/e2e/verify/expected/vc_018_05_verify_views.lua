-- Test oracle for VC-VERIFY-004: View Syntax Compatibility
-- Verifies unsupported/legacy view syntax does not emit unexpected SD-5xx
--
-- In expect_errors mode, this oracle validates diagnostics emitted by VERIFY.

return function(actual_doc, helpers)
    -- In expect_errors mode, actual_doc is nil and we check diagnostics
    if helpers.expect_errors then
        local test_errors = {}
        local function err(msg) table.insert(test_errors, msg) end

        local diag = helpers.diagnostics
        if not diag then
            return false, "No diagnostics available"
        end

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

        -- Verify no SD-5xx codes were emitted
        for code, _ in pairs(detected_codes) do
            if code:match("^SD%-5%d%d$") then
                err(string.format("Unexpected %s detected", code))
            end
        end

        -- Report what was detected (for debugging)
        if #test_errors > 0 then
            local detected_list = {}
            for code, count in pairs(detected_codes) do
                table.insert(detected_list, string.format("%s (%d)", code, count))
            end
            table.sort(detected_list)

            return false, "View test failed:\n  Issue: " ..
                table.concat(test_errors, "\n  Issue: ") ..
                "\n  Detected: " .. table.concat(detected_list, ", ")
        end

        return true, nil
    end

    -- Standard mode (not used for this test)
    return false, "This test requires expect_errors mode"
end
