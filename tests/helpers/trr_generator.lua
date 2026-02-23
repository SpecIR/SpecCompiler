-- TRR Generator: Reads JUnit XML → generates TR markdown
-- Usage: pandoc --lua-filter tests/helpers/trr_generator.lua \
--          --metadata junit_path=tests/reports/junit.xml \
--          --metadata output_path=docs/test_results/tr.md \
--          < /dev/null
--
-- Reads test results from JUnit XML, derives VC PIDs from test
-- filenames, and generates TR objects as markdown for inclusion
-- in the SVC document.

local speccompiler_home = os.getenv("SPECCOMPILER_HOME") or "."

-- ============================================
-- JUnit XML Parser
-- ============================================

local function parse_junit_xml(path)
    local f = io.open(path, "r")
    if not f then
        io.stderr:write("[trr] Error: Cannot open " .. path .. "\n")
        return {}
    end

    local tests = {}
    local current = nil
    local suite_timestamp = nil

    for line in f:lines() do
        local ts = line:match('<testsuite[^>]*timestamp="([^"]*)"')
        if ts then
            suite_timestamp = ts
        end

        if line:match("<testcase ") then
            local name = line:match('name="([^"]*)"')
            local classname = line:match('classname="([^"]*)"')
            local time = tonumber(line:match('time="([^"]*)"')) or 0

            if line:match("/>%s*$") then
                table.insert(tests, {
                    name = name, suite = classname,
                    time = time, status = "passed",
                    timestamp = suite_timestamp
                })
            else
                current = {
                    name = name, suite = classname,
                    time = time, status = "passed",
                    timestamp = suite_timestamp
                }
            end
        elseif current then
            if line:match("<skipped") then
                current.status = "skipped"
            elseif line:match("<failure") then
                current.status = "failed"
                current.message = line:match('message="([^"]*)"')
            elseif line:match("</testcase>") then
                table.insert(tests, current)
                current = nil
            end
        end
    end

    f:close()
    return tests
end

-- ============================================
-- PID Resolution
-- ============================================

local function resolve_vc_pid(test_name)
    local parts = {}
    for token in test_name:gmatch("[^_]+") do
        table.insert(parts, token)
    end
    if parts[1] ~= "vc" then return nil end
    for i = 2, #parts do
        if parts[i]:match("^%d+$") then
            local seq = string.format("%03d", tonumber(parts[i]))
            local domain = {}
            for j = 2, i - 1 do
                table.insert(domain, parts[j]:upper())
            end
            if #domain > 0 then
                return "VC-" .. table.concat(domain, "-") .. "-" .. seq
            end
            return "VC-" .. seq
        end
    end
    return nil
end

---Derive a unique TR PID from the test filename.
---Includes the TP sequence (second numeric token) to avoid duplicates
---when multiple TPs map to the same VC.
---E.g., vc_015_03_links -> TR-015-03, vc_pipe_007_01_sourcepos -> TR-PIPE-007-01
local function resolve_tr_pid(test_name)
    local parts = {}
    for token in test_name:gmatch("[^_]+") do
        table.insert(parts, token)
    end
    if parts[1] ~= "vc" then return nil end
    local vc_seq_idx = nil
    for i = 2, #parts do
        if parts[i]:match("^%d+$") then
            vc_seq_idx = i
            break
        end
    end
    if not vc_seq_idx then return nil end

    local vc_seq = string.format("%03d", tonumber(parts[vc_seq_idx]))
    local domain = {}
    for j = 2, vc_seq_idx - 1 do
        table.insert(domain, parts[j]:upper())
    end

    -- Find TP sequence (next numeric token after VC sequence)
    local tp_seq = nil
    if vc_seq_idx + 1 <= #parts and parts[vc_seq_idx + 1]:match("^%d+$") then
        tp_seq = string.format("%02d", tonumber(parts[vc_seq_idx + 1]))
    end

    local pid = "TR-"
    if #domain > 0 then
        pid = pid .. table.concat(domain, "-") .. "-"
    end
    pid = pid .. vc_seq
    if tp_seq then
        pid = pid .. "-" .. tp_seq
    end
    return pid
end

-- Cache for model directories that contain test suites
local _model_dirs = nil

local function get_model_dirs()
    if _model_dirs then return _model_dirs end
    _model_dirs = {}
    local handle = io.popen("ls -1d " .. speccompiler_home .. "/models/*/tests 2>/dev/null")
    if handle then
        for line in handle:lines() do
            local model = line:match("/models/([^/]+)/tests$")
            if model then
                table.insert(_model_dirs, model)
            end
        end
        handle:close()
    end
    return _model_dirs
end

local function derive_test_path(suite, test_name)
    if suite == "tests" then
        -- Model test suites all get classname="tests" (basename of models/*/tests/)
        -- Probe each model directory to find which one contains this test file
        for _, model in ipairs(get_model_dirs()) do
            local path = speccompiler_home .. "/models/" .. model .. "/tests/" .. test_name .. ".md"
            local f = io.open(path, "r")
            if f then
                f:close()
                return "models/" .. model .. "/tests/" .. test_name .. ".md"
            end
        end
    end
    return "tests/e2e/" .. (suite or "unknown") .. "/" .. test_name .. ".md"
end

-- ============================================
-- Domain Grouping
-- ============================================

local domain_labels = {
    PIPE = "Pipeline",
    STOR = "Storage",
    TYPE = "Types",
    EXT  = "Extension",
    OUT  = "Output",
    SDN  = "SW Docs Model",
    WEB  = "HTML5 Postprocessor",
    DEF  = "Default Model",
}

local domain_order = { "PIPE", "STOR", "TYPE", "EXT", "OUT", "SDN", "WEB", "DEF" }

local function get_domain(vc_pid)
    -- Check for explicit domain prefix (e.g., VC-PIPE-007, VC-OUT-001)
    local prefix = vc_pid:match("^VC%-(%u+)%-")
    if prefix then return prefix end

    -- Map numeric VCs to domains by range
    local num = tonumber(vc_pid:match("^VC%-(%d+)$"))
    if not num then return "OTHER" end
    if num <= 6 then return "PIPE"
    elseif num <= 11 or num == 33 then return "STOR"
    elseif num <= 18 then return "TYPE"
    elseif num <= 26 then return "EXT"
    elseif num <= 32 then return "OUT"
    else return "OTHER"
    end
end

-- ============================================
-- Markdown Generation
-- ============================================

local function status_to_result(status)
    if status == "passed" then return "Pass"
    elseif status == "failed" then return "Fail"
    elseif status == "skipped" then return "Blocked"
    else return "Not Run"
    end
end

local function xml_unescape(str)
    if not str then return nil end
    return str:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        :gsub("&quot;", '"'):gsub("&apos;", "'")
end

local function generate_tr_block(test, vc_pid, tr_pid)
    local lines = {}
    local title = test.name:gsub("^vc_", ""):gsub("_", " ")
    title = title:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)

    table.insert(lines, "### TR: " .. title .. " @" .. tr_pid)
    table.insert(lines, "")
    table.insert(lines, "> result: " .. status_to_result(test.status))
    table.insert(lines, "")
    table.insert(lines, "> traceability: [" .. vc_pid .. "](@)")
    table.insert(lines, "")
    table.insert(lines, "> test_file: " .. derive_test_path(test.suite, test.name))
    table.insert(lines, "")
    table.insert(lines, "> duration_ms: " .. tostring(math.floor(test.time * 1000)))
    table.insert(lines, "")
    table.insert(lines, "> execution_date: " .. os.date("%Y-%m-%d"))
    table.insert(lines, "")
    table.insert(lines, "> executed_by: E2E Test Runner")

    if test.status == "failed" and test.message then
        table.insert(lines, "")
        table.insert(lines, "> failure_reason: " .. xml_unescape(test.message))
    end

    table.insert(lines, "")
    return table.concat(lines, "\n")
end

-- ============================================
-- Main (Pandoc filter entry point)
-- ============================================

function Meta(meta)
    local junit_path = speccompiler_home .. "/tests/reports/junit.xml"
    local output_path = speccompiler_home .. "/docs/test_results/tr.md"

    if meta.junit_path then
        junit_path = pandoc.utils.stringify(meta.junit_path)
    end
    if meta.output_path then
        output_path = pandoc.utils.stringify(meta.output_path)
    end

    io.stderr:write("[trr] Reading JUnit XML from: " .. junit_path .. "\n")
    local tests = parse_junit_xml(junit_path)
    io.stderr:write("[trr] Found " .. #tests .. " test results\n")

    -- Group TRs by domain
    local domain_trs = {}
    local unmapped = 0

    for _, test in ipairs(tests) do
        local vc_pid = resolve_vc_pid(test.name)
        local tr_pid = resolve_tr_pid(test.name)
        if vc_pid and tr_pid then
            local domain = get_domain(vc_pid)

            if not domain_trs[domain] then
                domain_trs[domain] = {}
            end
            table.insert(domain_trs[domain], {
                test = test, vc_pid = vc_pid, tr_pid = tr_pid
            })
        else
            unmapped = unmapped + 1
        end
    end

    if unmapped > 0 then
        io.stderr:write("[trr] Skipped " .. unmapped .. " tests without VC mapping\n")
    end

    -- Generate markdown grouped by domain
    local output = {}

    for _, domain_key in ipairs(domain_order) do
        local trs = domain_trs[domain_key]
        if trs then
            table.sort(trs, function(a, b) return a.tr_pid < b.tr_pid end)
            for _, tr in ipairs(trs) do
                table.insert(output, generate_tr_block(tr.test, tr.vc_pid, tr.tr_pid))
            end
        end
    end

    -- Handle domains not in standard order
    for domain_key, trs in pairs(domain_trs) do
        local found = false
        for _, dk in ipairs(domain_order) do
            if dk == domain_key then found = true; break end
        end
        if not found then
            table.sort(trs, function(a, b) return a.tr_pid < b.tr_pid end)
            for _, tr in ipairs(trs) do
                table.insert(output, generate_tr_block(tr.test, tr.vc_pid, tr.tr_pid))
            end
        end
    end

    local content = table.concat(output, "\n")

    -- Write output
    local dir = output_path:match("(.*/)")
    if dir then
        os.execute("mkdir -p " .. dir)
    end

    local f = io.open(output_path, "w")
    if not f then
        io.stderr:write("[trr] Error: Cannot write to " .. output_path .. "\n")
        os.exit(1)
    end
    f:write(content)
    f:close()

    -- Count results
    local total = 0
    for _, trs in pairs(domain_trs) do
        for _ in pairs(trs) do total = total + 1 end
    end
    io.stderr:write("[trr] Generated TR objects → " .. output_path .. "\n")
end

return {{Meta = Meta}}
