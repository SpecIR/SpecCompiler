-- JUnit XML report generation
-- Generates JUnit-compatible XML reports for CI/CD integration

local M = {}

M.report_path = "tests/reports/junit.xml"

-- Global results collector
M.suites = {}
M.current_suite = nil

--- Start collecting results for a new suite
---@param suite_name string
function M.start_suite(suite_name)
    M.current_suite = {
        name = suite_name,
        tests = {},
        time = 0,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        start_time = os.clock()
    }
end

--- Record a test result
---@param test_name string
---@param status string "passed"|"failed"|"skipped"
---@param duration number Duration in seconds
---@param failure_message string|nil
---@param failure_type string|nil
---@param vc_id string|nil Associated VC identifier
function M.record_test(test_name, status, duration, failure_message, failure_type, vc_id)
    if not M.current_suite then return end

    table.insert(M.current_suite.tests, {
        name = test_name,
        classname = M.current_suite.name,
        time = duration or 0,
        status = status,
        failure_message = failure_message,
        failure_type = failure_type or "AssertionError",
        vc_id = vc_id
    })
end

--- Finish the current suite
function M.end_suite()
    if not M.current_suite then return end

    M.current_suite.time = os.clock() - M.current_suite.start_time
    M.current_suite.start_time = nil  -- Remove internal field

    table.insert(M.suites, M.current_suite)
    M.current_suite = nil
end

--- Escape XML special characters
---@param str string
---@return string
local function xml_escape(str)
    if not str then return "" end
    return tostring(str)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&apos;")
end

--- Generate JUnit XML from collected results
---@return string xml
function M.generate_xml()
    local lines = {}

    -- XML header
    table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')

    -- Calculate totals
    local total_tests = 0
    local total_failures = 0
    local total_skipped = 0
    local total_time = 0

    for _, suite in ipairs(M.suites) do
        for _, test in ipairs(suite.tests) do
            total_tests = total_tests + 1
            total_time = total_time + test.time
            if test.status == "failed" then
                total_failures = total_failures + 1
            elseif test.status == "skipped" then
                total_skipped = total_skipped + 1
            end
        end
    end

    -- testsuites root element
    table.insert(lines, string.format(
        '<testsuites tests="%d" failures="%d" skipped="%d" time="%.3f">',
        total_tests, total_failures, total_skipped, total_time
    ))

    -- Each suite
    for _, suite in ipairs(M.suites) do
        local suite_tests = #suite.tests
        local suite_failures = 0
        local suite_skipped = 0

        for _, test in ipairs(suite.tests) do
            if test.status == "failed" then
                suite_failures = suite_failures + 1
            elseif test.status == "skipped" then
                suite_skipped = suite_skipped + 1
            end
        end

        table.insert(lines, string.format(
            '  <testsuite name="%s" tests="%d" failures="%d" skipped="%d" time="%.3f" timestamp="%s">',
            xml_escape(suite.name),
            suite_tests,
            suite_failures,
            suite_skipped,
            suite.time,
            suite.timestamp
        ))

        -- Each test case
        for _, test in ipairs(suite.tests) do
            if test.status == "skipped" then
                table.insert(lines, string.format(
                    '    <testcase name="%s" classname="%s" time="%.3f">',
                    xml_escape(test.name),
                    xml_escape(test.classname),
                    test.time
                ))
                if test.vc_id and test.vc_id ~= "" then
                    table.insert(lines, '      <properties>')
                    table.insert(lines, string.format(
                        '        <property name="vc_id" value="%s"/>',
                        xml_escape(test.vc_id)
                    ))
                    table.insert(lines, '      </properties>')
                end
                table.insert(lines, '      <skipped/>')
                table.insert(lines, '    </testcase>')
            elseif test.status == "failed" then
                table.insert(lines, string.format(
                    '    <testcase name="%s" classname="%s" time="%.3f">',
                    xml_escape(test.name),
                    xml_escape(test.classname),
                    test.time
                ))
                if test.vc_id and test.vc_id ~= "" then
                    table.insert(lines, '      <properties>')
                    table.insert(lines, string.format(
                        '        <property name="vc_id" value="%s"/>',
                        xml_escape(test.vc_id)
                    ))
                    table.insert(lines, '      </properties>')
                end
                table.insert(lines, string.format(
                    '      <failure type="%s" message="%s"/>',
                    xml_escape(test.failure_type),
                    xml_escape(test.failure_message)
                ))
                table.insert(lines, '    </testcase>')
            else
                if test.vc_id and test.vc_id ~= "" then
                    table.insert(lines, string.format(
                        '    <testcase name="%s" classname="%s" time="%.3f">',
                        xml_escape(test.name),
                        xml_escape(test.classname),
                        test.time
                    ))
                    table.insert(lines, '      <properties>')
                    table.insert(lines, string.format(
                        '        <property name="vc_id" value="%s"/>',
                        xml_escape(test.vc_id)
                    ))
                    table.insert(lines, '      </properties>')
                    table.insert(lines, '    </testcase>')
                else
                    table.insert(lines, string.format(
                        '    <testcase name="%s" classname="%s" time="%.3f"/>',
                        xml_escape(test.name),
                        xml_escape(test.classname),
                        test.time
                    ))
                end
            end
        end

        table.insert(lines, '  </testsuite>')
    end

    table.insert(lines, '</testsuites>')

    return table.concat(lines, "\n")
end

--- Write XML report to file
---@param path string|nil Output path (default: M.report_path)
---@return boolean success
function M.write_report(path)
    path = path or M.report_path

    -- Ensure directory exists
    local dir = path:match("(.*/)")
    if dir then
        os.execute("mkdir -p " .. dir)
    end

    local xml = M.generate_xml()
    local f = io.open(path, "w")
    if f then
        f:write(xml)
        f:close()
        return true
    end
    return false
end

--- Write partial results to a temp file (for subprocess aggregation)
---@param path string Output path
---@return boolean success
function M.write_partial(path)
    -- Ensure directory exists
    local dir = path:match("(.*/)")
    if dir then
        os.execute("mkdir -p " .. dir)
    end

    -- Write current suites as partial JSON-like format for later merge
    local f = io.open(path, "w")
    if not f then return false end

    for _, suite in ipairs(M.suites) do
        f:write("SUITE:" .. suite.name .. "\n")
        f:write("TIMESTAMP:" .. suite.timestamp .. "\n")
        f:write("TIME:" .. suite.time .. "\n")
        for _, test in ipairs(suite.tests) do
            f:write(string.format("TEST:%s|%s|%.6f|%s|%s|%s\n",
                test.name,
                test.status,
                test.time,
                test.failure_message or "",
                test.failure_type or "",
                test.vc_id or ""
            ))
        end
        f:write("END_SUITE\n")
    end

    f:close()
    return true
end

--- Load partial results from a file
---@param path string Input path
---@return boolean success
function M.load_partial(path)
    local f = io.open(path, "r")
    if not f then return false end

    local current_suite = nil

    for line in f:lines() do
        if line:match("^SUITE:") then
            current_suite = {
                name = line:sub(7),
                tests = {},
                time = 0,
                timestamp = ""
            }
        elseif line:match("^TIMESTAMP:") and current_suite then
            current_suite.timestamp = line:sub(11)
        elseif line:match("^TIME:") and current_suite then
            current_suite.time = tonumber(line:sub(6)) or 0
        elseif line:match("^TEST:") and current_suite then
            local data = line:sub(6)
            local name, status, time, msg, ftype, vc_id = data:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)")
            if not name then
                name, status, time, msg, ftype = data:match("([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)")
                vc_id = ""
            end
            table.insert(current_suite.tests, {
                name = name,
                classname = current_suite.name,
                status = status,
                time = tonumber(time) or 0,
                failure_message = msg ~= "" and msg or nil,
                failure_type = ftype ~= "" and ftype or nil,
                vc_id = vc_id ~= "" and vc_id or nil
            })
        elseif line == "END_SUITE" and current_suite then
            table.insert(M.suites, current_suite)
            current_suite = nil
        end
    end

    f:close()
    return true
end

--- Reset all collected data
function M.reset()
    M.suites = {}
    M.current_suite = nil
end

return M
