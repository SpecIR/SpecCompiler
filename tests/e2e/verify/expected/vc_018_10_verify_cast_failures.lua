-- Oracle: spec-level cast failures (DATE attribute with invalid value).
-- Exercises the second UNION branch of view_object_cast_failures
-- where owner_object_id IS NULL (specification-level attributes).
-- SRS has a "date" attribute of type DATE; "not-a-date" fails the cast.

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

    if not detected["invalid_cast"] then
        local found = {}
        for code, count in pairs(detected) do
            table.insert(found, string.format("%s(%d)", code, count))
        end
        table.sort(found)
        return false,
            "Expected invalid_cast for spec-level DATE attribute (date: not-a-date) but not detected.\n" ..
            "Detected: " .. (next(detected) and table.concat(found, ", ") or "nothing")
    end

    return true, nil
end
