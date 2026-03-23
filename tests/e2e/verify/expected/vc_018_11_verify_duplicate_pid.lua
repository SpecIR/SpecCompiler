-- Oracle: duplicate PID detection.
-- Two HLR objects share @HLR-DUPE, triggering object_duplicate_pid.
-- HLR-UNIQUE is a control and must NOT appear in the proof view.

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

    if not detected["object_duplicate_pid"] then
        local found = {}
        for code, count in pairs(detected) do
            table.insert(found, string.format("%s(%d)", code, count))
        end
        table.sort(found)
        return false,
            "Expected object_duplicate_pid for @HLR-DUPE but not detected.\n" ..
            "Detected: " .. (next(detected) and table.concat(found, ", ") or "nothing")
    end

    -- Both duplicate objects should be reported (exactly 2 diagnostics)
    if detected["object_duplicate_pid"] ~= 2 then
        return false, string.format(
            "Expected exactly 2 object_duplicate_pid diagnostics (both @HLR-DUPE objects), got %d",
            detected["object_duplicate_pid"])
    end

    return true, nil
end
