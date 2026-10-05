-- Oracle: citation links (@cite/@citep) are not unresolved relations; a broken @ link is
-- Expected policy_key codes are listed in expected_codes; forbidden_codes must
-- not appear (control objects and non-violations).

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
        ["unresolved_relation"] = 1,
    }
    local forbidden_codes = { "ambiguous_relation", }

    for code, count in pairs(expected_codes) do
        if (detected[code] or 0) ~= count then
            err(string.format("Expected %s x%d but detected x%d", code, count, detected[code] or 0))
        end
    end
    for _, code in ipairs(forbidden_codes) do
        if detected[code] then
            err(string.format("Unexpected %s x%d", code, detected[code]))
        end
    end

    if #test_errors > 0 then
        local found = {}
        for code, count in pairs(detected) do
            table.insert(found, string.format("%s(%d)", code, count))
        end
        table.sort(found)
        return false, "vc_018_18_verify_unresolved_citation failed:\n  " .. table.concat(test_errors, "\n  ") ..
            "\n  Detected: " .. table.concat(found, ", ")
    end

    return true, nil
end
