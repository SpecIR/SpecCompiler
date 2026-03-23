-- Oracle: multiple datatype cast failures at spec and object level.
-- Exercises INTEGER, REAL, BOOLEAN, DATE spec-level casts AND object-level ENUM.
-- Verifies XHTML exclusion: notes attribute must NOT trigger invalid_cast.
--
-- Expected invalid_cast diagnostics (5 total):
--   Spec-level:  build_number (INTEGER), progress (REAL),
--                is_stable (BOOLEAN), release_date (DATE)
--   Object-level: priority (ENUM) on HLR-CAST-ENUM

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
            "Expected invalid_cast for multiple datatypes but not detected.\n" ..
            "Detected: " .. (next(detected) and table.concat(found, ", ") or "nothing")
    end

    -- Expect exactly 5 invalid_cast diagnostics:
    --   4 spec-level: build_number (INTEGER), progress (REAL),
    --                 is_stable (BOOLEAN), release_date (DATE)
    --   1 object-level: priority (ENUM) on HLR-CAST-ENUM
    if detected["invalid_cast"] ~= 5 then
        return false, string.format(
            "Expected exactly 5 invalid_cast diagnostics " ..
            "(4 spec-level: INTEGER/REAL/BOOLEAN/DATE + 1 object-level: ENUM), got %d",
            detected["invalid_cast"])
    end

    -- Verify XHTML exclusion via DB query:
    -- The "notes" attribute (XHTML) must NOT appear in view_object_cast_failures
    if helpers.db_file then
        local ok, sqlite3 = pcall(require, "lsqlite3")
        if ok and sqlite3 then
            local db = sqlite3.open(helpers.db_file, sqlite3.OPEN_READONLY)
            if db then
                local xhtml_count = 0
                for _ in db:nrows(
                    "SELECT * FROM view_object_cast_failures WHERE attribute_name = 'notes'"
                ) do
                    xhtml_count = xhtml_count + 1
                end
                db:close()

                if xhtml_count > 0 then
                    return false, string.format(
                        "XHTML attribute 'notes' appeared in cast failures (%d rows) " ..
                        "-- NOT IN ('XHTML') clause may be broken",
                        xhtml_count)
                end
            end
        end
    end

    return true, nil
end
