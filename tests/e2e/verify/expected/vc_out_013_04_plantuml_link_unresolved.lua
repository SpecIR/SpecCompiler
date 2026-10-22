-- Oracle for VC-OUT-013 (TP 04): an unresolved link inside a PlantUML diagram
-- yields exactly one unresolved_relation, reported at the diagram line that
-- holds it (fence line + line within the block); resolved diagram links and
-- body links raise nothing.

return function(_, helpers)
    if not helpers.expect_errors then
        return false, "This test requires expect_errors mode"
    end
    local diag = helpers.diagnostics
    if not diag then
        return false, "No diagnostics available"
    end

    local test_name = "vc_out_013_04_plantuml_link_unresolved"
    local f = io.open(helpers.suite_dir .. "/" .. test_name .. ".md", "r")
    if not f then return false, "fixture not readable" end
    local md = f:read("*a")
    f:close()
    local expected_line
    local n = 0
    for line in (md .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        if line:find("[NOPE-999](@)", 1, true) then expected_line = n break end
    end

    local unresolved = {}
    for _, list in ipairs({ diag.errors or {}, diag.warnings or {} }) do
        for _, d in ipairs(list) do
            if d.code == "unresolved_relation" then unresolved[#unresolved + 1] = d end
        end
    end

    local function describe()
        local out = {}
        for _, d in ipairs(unresolved) do
            out[#out + 1] = string.format("%s:%s %s", tostring(d.file), tostring(d.line), tostring(d.message))
        end
        return table.concat(out, "; ")
    end

    if #unresolved ~= 1 then
        return false, string.format("Expected 1 unresolved_relation, got %d: %s", #unresolved, describe())
    end
    local d = unresolved[1]
    if not tostring(d.message):find("NOPE-999", 1, true) then
        return false, "unresolved_relation is not about NOPE-999: " .. describe()
    end
    if d.line ~= expected_line then
        return false, string.format("unresolved_relation at line %s, expected diagram line %s: %s",
            tostring(d.line), tostring(expected_line), describe())
    end
    if not tostring(d.file):find(test_name .. ".md", 1, true) then
        return false, "unresolved_relation reported in wrong file: " .. describe()
    end
    return true
end
