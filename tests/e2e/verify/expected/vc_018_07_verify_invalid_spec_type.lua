-- Oracle: Unknown specification type fallback behavior.
-- UNKNOWN_SPEC triggers exactly 1 WARN diagnostic from the parser fallback.
-- The fallback to SPEC means the spec_invalid_type proof should NOT fire.

return function(_, helpers)
    if not helpers.expect_errors then
        return false, "This test requires expect_errors mode"
    end

    local diag = helpers.diagnostics
    if not diag then
        return false, "No diagnostics available"
    end

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

    if not detected_codes["WARN"] then
        local detected_list = {}
        for code, count in pairs(detected_codes) do
            detected_list[#detected_list + 1] = string.format("%s (%d)", code, count)
        end
        table.sort(detected_list)
        return false, "Expected WARN fallback diagnostic but it was not detected. Detected: " .. table.concat(detected_list, ", ")
    end

    -- Exactly 1 WARN: only the unknown type fallback, no cascading warnings
    if detected_codes["WARN"] ~= 1 then
        return false, string.format(
            "Expected exactly 1 WARN diagnostic for UNKNOWN_SPEC fallback, got %d",
            detected_codes["WARN"])
    end

    -- Fallback to SPEC should prevent the spec_invalid_type proof from firing
    if detected_codes["spec_invalid_type"] then
        return false, string.format(
            "Unexpected spec_invalid_type proof fired (%d times) -- fallback should have prevented this",
            detected_codes["spec_invalid_type"])
    end

    return true
end
