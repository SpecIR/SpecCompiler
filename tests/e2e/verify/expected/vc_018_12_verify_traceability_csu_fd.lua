-- Oracle: CSU/FD traceability proof coverage.
-- CSU-ORPHAN has no inbound FD relation -> traceability_csu_to_fd
-- FD-ORPHAN has no outbound CSU relation -> traceability_fd_to_csu
-- CSU-LINKED + FD-LINKED are properly linked (control).

return function(_, helpers)
    if not helpers.expect_errors then
        return false, "This test requires expect_errors mode"
    end

    local diag = helpers.diagnostics
    if not diag then
        return false, "No diagnostics available"
    end

    local detected = {}
    for _, e in ipairs(diag.errors or {}) do
        if e.code then detected[e.code] = (detected[e.code] or 0) + 1 end
    end
    for _, w in ipairs(diag.warnings or {}) do
        if w.code then detected[w.code] = (detected[w.code] or 0) + 1 end
    end

    local test_errors = {}
    local function err(msg) table.insert(test_errors, msg) end

    local expected_codes = {
        ["traceability_csu_to_fd"] = "CSU without FD allocation",
        ["traceability_fd_to_csu"] = "FD without CSU traceability",
    }

    for code, desc in pairs(expected_codes) do
        if not detected[code] then
            err(string.format("Expected %s (%s) but not detected", code, desc))
        end
    end

    if #test_errors > 0 then
        local found = {}
        for code, count in pairs(detected) do
            table.insert(found, string.format("%s(%d)", code, count))
        end
        table.sort(found)
        return false,
            "CSU/FD traceability test failed:\n  " ..
            table.concat(test_errors, "\n  ") ..
            "\n  Detected: " .. table.concat(found, ", ")
    end

    return true, nil
end
