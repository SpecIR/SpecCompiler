-- SpecCompiler E2E Test Runner
-- Pandoc filter that discovers and executes E2E tests
-- Usage: pandoc --lua-filter tests/runner.lua --metadata suite=<name> < /dev/null

local M = {}

-- Load dkjson for proper JSON parsing
local speccompiler_home = os.getenv("SPECCOMPILER_HOME") or "."
package.path = speccompiler_home .. "/vendor/?.lua;" .. speccompiler_home .. "/tests/?.lua;" .. speccompiler_home .. "/tests/helpers/?.lua;" .. package.path
local json = require("dkjson")

-- Load AST comparison and domain helpers for Lua oracles
local ast_compare = require("ast_compare")
local domain_helpers = require("domain_helpers")

-- Load SpecCompiler engine for in-process execution (enables coverage)
local engine = require("core.engine")

-- Lazy-loaded reporters (only loaded when enabled)
local junit = nil
local coverage = nil

-- Configuration from metadata
local config = {
    suite = nil,           -- Suite filter (nil = all)
    test = nil,            -- Test filter (nil = all in suite)
    coverage = false,
    junit = false,
    report_dir = "tests/reports"
}

-- Results tracking
local results = {
    passed = 0,
    failed = 0,
    skipped = 0,
    tests = {}
}

-- Capability cache for environment-dependent tests
local chart_renderer_capable = nil
local chart_renderer_reason = nil

-- ============================================
-- File System Helpers
-- ============================================

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function mkdir_p(path)
    os.execute("mkdir -p " .. path)
end

local function list_dirs(path)
    local dirs = {}
    local handle = io.popen("find " .. path .. " -maxdepth 1 -type d 2>/dev/null | sort")
    if handle then
        for line in handle:lines() do
            if line ~= path then
                table.insert(dirs, line)
            end
        end
        handle:close()
    end
    return dirs
end

local function list_files(path, pattern)
    local files = {}
    local cmd = "find " .. path .. " -maxdepth 1 -type f -name '" .. pattern .. "' 2>/dev/null | sort"
    local handle = io.popen(cmd)
    if handle then
        for line in handle:lines() do
            table.insert(files, line)
        end
        handle:close()
    end
    return files
end

local function basename(path, ext)
    local name = path:match("([^/]+)$")
    if ext and name:sub(-#ext) == ext then
        name = name:sub(1, -#ext - 1)
    end
    return name
end

---Extract VC naming metadata from a test filename.
---Expected pattern: vc_<domain...>_<NNN>_<description>
---@param test_name string basename without extension
---@return string|nil short_id
---@return string|nil qualified_id
---@return string|nil sequence
---@return string|nil error
local function extract_vc_from_filename(test_name)
    local parts = {}
    for token in test_name:gmatch("[^_]+") do
        table.insert(parts, token)
    end

    if parts[1] ~= "vc" then
        return nil, nil, nil, "test file must start with 'vc_'"
    end

    local seq_index = nil
    for i = 2, #parts do
        if parts[i]:match("^%d+$") then
            seq_index = i
            break
        end
    end
    if not seq_index then
        return nil, nil, nil, "test file must include numeric VC sequence token (e.g. '_002_')"
    end

    local seq = parts[seq_index]
    if #seq < 3 and tonumber(seq) then
        seq = string.format("%03d", tonumber(seq))
    end

    local short_id = "VC-" .. seq
    local domain_tokens = {}
    for i = 2, seq_index - 1 do
        table.insert(domain_tokens, parts[i]:upper())
    end

    local qualified_id = short_id
    if #domain_tokens > 0 then
        qualified_id = "VC-" .. table.concat(domain_tokens, "-") .. "-" .. seq
    end

    return short_id, qualified_id, seq, nil
end


local function dirname(path)
    return path:match("(.*/)")
end

local function command_succeeds(cmd)
    local ok, _, code = os.execute(cmd)
    if type(ok) == "number" then
        return ok == 0, ok
    end
    if ok == true then
        return true, 0
    end
    return false, code or -1
end

local function is_chart_renderer_available()
    if chart_renderer_capable ~= nil then
        return chart_renderer_capable, chart_renderer_reason
    end

    local root = speccompiler_home or "."
    local ts_renderer = root .. "/src/tools/echarts-render.ts"
    local has_deno = command_succeeds("command -v deno >/dev/null 2>&1")

    if has_deno and file_exists(ts_renderer) then
        local ts_cmd = string.format(
            "deno run --allow-read --allow-write --allow-env --allow-net --allow-ffi --allow-sys %q --help >/dev/null 2>&1",
            ts_renderer
        )
        local ts_ok, ts_exit = command_succeeds(ts_cmd)
        if ts_ok then
            chart_renderer_capable = true
            chart_renderer_reason = nil
            return chart_renderer_capable, chart_renderer_reason
        end

        chart_renderer_reason = "TypeScript renderer unavailable (exit code " .. tostring(ts_exit) .. ")"
    end

    local bin_renderer = root .. "/bin/echarts-render"
    if not file_exists(bin_renderer) then
        chart_renderer_capable = false
        if not chart_renderer_reason then
            chart_renderer_reason = "renderer not found (neither TypeScript nor binary)"
        end
        return chart_renderer_capable, chart_renderer_reason
    end

    local cmd = string.format("%q --help >/dev/null 2>&1", bin_renderer)
    local ok, exit_code = command_succeeds(cmd)
    chart_renderer_capable = ok
    if ok then
        chart_renderer_reason = nil
    else
        chart_renderer_reason = (chart_renderer_reason and (chart_renderer_reason .. "; "))
            or ""
        chart_renderer_reason = chart_renderer_reason
            .. "binary renderer unavailable (exit code " .. tostring(exit_code) .. ")"
    end
    return chart_renderer_capable, chart_renderer_reason
end

local function clean_build_dirs()
    local e2e_dir = "tests/e2e"
    local suites = list_dirs(e2e_dir)
    for _, suite_dir in ipairs(suites) do
        local build_dir = suite_dir .. "/build"
        os.execute("rm -rf " .. build_dir .. " 2>/dev/null")
    end

    -- Also clean model-defined test suite build directories
    local models_dir = speccompiler_home .. "/models"
    local model_dirs = list_dirs(models_dir)
    for _, model_dir in ipairs(model_dirs) do
        local model_build_dir = model_dir .. "/tests/build"
        os.execute("rm -rf " .. model_build_dir .. " 2>/dev/null")
    end
end

-- ============================================
-- YAML Parsing (simple key: value)
-- ============================================

local function parse_yaml(content)
    local result = {}
    local current_table = result
    local indent_stack = {{t = result, indent = -1}}

    for line in content:gmatch("[^\n]+") do
        local indent = #(line:match("^(%s*)") or "")
        local key, value = line:match("^%s*([%w_]+):%s*(.*)$")

        if key then
            -- Pop stack to find parent at lower indent
            while #indent_stack > 1 and indent_stack[#indent_stack].indent >= indent do
                table.remove(indent_stack)
            end
            current_table = indent_stack[#indent_stack].t

            if value == "" then
                -- Nested table
                current_table[key] = {}
                table.insert(indent_stack, {t = current_table[key], indent = indent})
            else
                -- Simple value
                current_table[key] = value
            end
        end
    end

    return result
end

-- ============================================
-- Test Execution
-- ============================================

local function find_expected_file(suite_dir, test_name)
    local expected_dir = suite_dir .. "/expected"
    -- Lua oracles first (primary format), then other formats
    local extensions = {".lua", ".docx", ".html", ".md"}

    for _, ext in ipairs(extensions) do
        local path = expected_dir .. "/" .. test_name .. ext
        if file_exists(path) then
            return path, ext
        end
    end

    return nil, nil
end

local function run_speccompiler(input_file, suite_dir, test_name, output_format)
    local build_dir = suite_dir .. "/build"
    local output_file = build_dir .. "/" .. test_name .. "." .. output_format
    local db_file = build_dir .. "/specir.db"

    mkdir_p(build_dir)

    -- Remove stale DB and journal files from previous test
    -- (oracle keeps DB alive between runs; WAL/SHM can cause corruption on WSL2)
    os.remove(db_file)
    os.remove(db_file .. "-wal")
    os.remove(db_file .. "-shm")
    os.remove(db_file .. "-journal")

    -- Build config programmatically (no subprocess!)
    local suite_config = parse_yaml(read_file(suite_dir .. "/suite.yaml") or "")
    local speccompiler_home_local = os.getenv("SPECCOMPILER_HOME") or "."

    -- Structure matches config.extract_metadata() return value
    local project_info = {
        project = {
            code = (suite_config.project and suite_config.project.code) or "TEST",
            name = (suite_config.project and suite_config.project.name) or "Test"
        },
        template = suite_config.template or "default",
        files = { suite_dir .. "/" .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = output_format,
        outputs = {
            { format = output_format, path = output_file }
        },
        db_file = db_file,
        logging = { level = "WARN" },
        validation = suite_config.validation,
        html5 = suite_config.html5,
        docx = suite_config.docx,
        bibliography = suite_config.bibliography,
        csl = suite_config.csl
    }

    -- Run SpecCompiler directly (same process = coverage works!)
    -- Capture diagnostics return value from engine.run_project
    local diag = nil
    local ok, err = pcall(function()
        diag = engine.run_project(project_info)
    end)

    -- DB file is kept alive for oracle access (cleaned by clean_build_dirs)

    -- Return diagnostics along with success/failure
    return ok, ok and nil or tostring(err), output_file, diag, suite_config, db_file
end

-- Check if a table is an attribute array (array of [key, value] string pairs)
local function is_attr_array(t)
    if type(t) ~= "table" then return false end
    -- Check for non-numeric keys (dicts are NOT attr arrays)
    for k, _ in pairs(t) do
        if type(k) ~= "number" then return false end
    end
    if #t == 0 then return true end  -- Empty arrays are valid
    -- Check if all elements are [string, string] pairs
    for _, v in ipairs(t) do
        if type(v) ~= "table" or #v ~= 2 then return false end
        if type(v[1]) ~= "string" or type(v[2]) ~= "string" then return false end
    end
    return true
end

-- Compare two attribute arrays as unordered sets
local function attrs_equal(a, b)
    if #a ~= #b then return false end

    -- Build a set from b
    local b_set = {}
    for _, pair in ipairs(b) do
        b_set[pair[1] .. "\0" .. pair[2]] = true
    end

    -- Check all pairs in a exist in b
    for _, pair in ipairs(a) do
        if not b_set[pair[1] .. "\0" .. pair[2]] then
            return false
        end
    end

    return true
end

-- Deep compare two values (handles tables recursively)
local function deep_equal(a, b)
    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= "table" then
        return a == b
    end

    -- Special handling for Pandoc attribute arrays (unordered)
    if is_attr_array(a) and is_attr_array(b) then
        return attrs_equal(a, b)
    end

    -- Compare tables
    local checked = {}
    for k, v in pairs(a) do
        checked[k] = true
        if not deep_equal(v, b[k]) then
            return false
        end
    end

    for k, _ in pairs(b) do
        if not checked[k] then
            return false
        end
    end

    return true
end

local function compare_json(actual_path, expected_path)
    local actual_str = read_file(actual_path)
    local expected_str = read_file(expected_path)

    if not actual_str then
        return false, "Actual file not found: " .. actual_path
    end
    if not expected_str then
        return false, "Expected file not found: " .. expected_path
    end

    -- First try exact string match (fastest, handles most cases)
    if actual_str == expected_str then
        return true, nil
    end

    -- Parse JSON to Lua tables using dkjson
    local actual, _, err1 = json.decode(actual_str)
    if not actual then
        return false, "Failed to parse actual JSON: " .. (err1 or "unknown error")
    end

    local expected, _, err2 = json.decode(expected_str)
    if not expected then
        return false, "Failed to parse expected JSON: " .. (err2 or "unknown error")
    end

    -- Semantic comparison using deep_equal
    if deep_equal(actual, expected) then
        return true, nil
    end

    return false, "JSON content differs semantically"
end

---Normalize HTML for version-independent comparison.
---Strips inline data-pos tracking spans and sourcepos attributes.
local function normalize_html(html)
    -- Strip <style>...</style> blocks (template CSS varies across Pandoc versions)
    html = html:gsub("<style[^>]*>.-</style>", "")
    -- Replace tracking span pairs: <span data-pos="...">CONTENT</span> → CONTENT
    local prev
    repeat
        prev = html
        html = html:gsub('<span data%-pos="[^"]*"[^>]*>(.-)</span>', "%1")
    until html == prev
    -- Strip sourcepos tracking attributes from block-level elements
    html = html:gsub(' data%-wrapper="[^"]*"', "")
    html = html:gsub(' wrapper="[^"]*"', "")
    html = html:gsub(' data%-pos="[^"]*"', "")
    -- Normalize whitespace for stable comparison
    html = html:gsub("%s+", " ")
    html = html:gsub("> <", "><")
    return html
end

local function compare_files(actual_path, expected_path, ext)
    -- Lua oracles are handled in run_test() directly
    -- This function handles non-Lua formats (docx, html, md)
    local actual = read_file(actual_path)
    local expected = read_file(expected_path)

    if not actual then
        return false, "Actual file not found: " .. actual_path
    end
    if not expected then
        return false, "Expected file not found: " .. expected_path
    end

    -- For HTML, normalize data-pos tracking for Pandoc version independence
    if ext == ".html" then
        actual = normalize_html(actual)
        expected = normalize_html(expected)
    end

    if actual == expected then
        return true, nil
    else
        return false, "Content differs"
    end
end

local function run_test(suite_dir, input_file)
    local test_name = basename(input_file, ".md")

    -- Charts currently depend on runtime capabilities that can be unavailable
    -- in restricted environments (e.g., sandboxed os.networkInterfaces access).
    if suite_dir:match("/floats$") and test_name == "vc_024_02_charts" then
        local available, reason = is_chart_renderer_available()
        if not available then
            return "skipped", "Chart renderer unavailable: " .. (reason or "unknown")
        end
    end

    local expected_path, ext = find_expected_file(suite_dir, test_name)

    if not expected_path then
        return "skipped", "No expected file found"
    end

    -- Determine output format from extension
    -- Lua oracles compare against JSON output
    local format_map = {
        [".lua"] = "json",
        [".docx"] = "docx",
        [".html"] = "html5",
        [".md"] = "markdown"
    }
    local output_format = format_map[ext] or "json"

    -- Run speccompiler (returns actual output path and diagnostics)
    local success, output, actual_path, diag, suite_config, db_file = run_speccompiler(input_file, suite_dir, test_name, output_format)

    -- Check if this suite expects errors (negative testing mode)
    local expect_errors = suite_config and suite_config.expect_errors == "true"

    -- Handle expect_errors mode for Lua oracles
    if expect_errors and ext == ".lua" then
        -- In expect_errors mode, we pass diagnostics to the oracle
        -- The oracle verifies expected errors were detected

        -- Load assertion function
        local assertion_fn = dofile(expected_path)
        if type(assertion_fn) ~= "function" then
            return "failed", "Expected file must return a function: " .. expected_path
        end

        -- Build helpers table with diagnostics
        local helpers = {
            assert_ast_equal = ast_compare.assert_equal,
            compare_ast = ast_compare.compare,
            format_report = ast_compare.format_report,
            strip_tracking_spans = ast_compare.strip_tracking_spans,
            inlines = ast_compare.inlines,
            blocks = ast_compare.blocks,
            para_content = ast_compare.para_content,
            domain = domain_helpers,
            options = {
                ignore_data_pos = false,
                strip_spans = false,
                collect_all = true,
                max_mismatches = 50
            },
            -- Pass diagnostics for expect_errors mode
            diagnostics = diag,
            expect_errors = true,
            db_file = db_file
        }

        -- Execute assertion with nil document (no output generated)
        local ok, result, err_msg = pcall(assertion_fn, nil, helpers)
        if not ok then
            return "failed", "Assertion error: " .. tostring(result)
        end

        -- Handle result
        if result == true then
            return "passed", nil
        elseif result == false then
            return "failed", err_msg or "Assertion returned false"
        elseif type(result) == "string" then
            return "failed", result
        else
            return "failed", "Assertion returned unexpected type: " .. type(result)
        end
    end

    -- Standard mode: pipeline must succeed
    if not success then
        return "failed", "SpecCompiler execution failed: " .. (output or "unknown error")
    end

    -- Compare output
    if ext == ".lua" then
        -- Lua AST assertion test
        local actual_json = read_file(actual_path)
        if not actual_json then
            return "failed", "Actual output file not found: " .. actual_path
        end

        -- Parse actual JSON to Pandoc document
        local actual_doc = pandoc.read(actual_json, "json")

        -- Load assertion function
        local assertion_fn = dofile(expected_path)
        if type(assertion_fn) ~= "function" then
            return "failed", "Expected file must return a function: " .. expected_path
        end

        -- Build helpers table for assertion function
        local helpers = {
            assert_ast_equal = ast_compare.assert_equal,
            compare_ast = ast_compare.compare,
            format_report = ast_compare.format_report,
            strip_tracking_spans = ast_compare.strip_tracking_spans,
            -- Tokenization helpers (use Pandoc to ensure consistent tokenization)
            inlines = ast_compare.inlines,
            blocks = ast_compare.blocks,
            para_content = ast_compare.para_content,
            domain = domain_helpers,
            options = {
                ignore_data_pos = false,
                strip_spans = false,
                collect_all = true,
                max_mismatches = 50
            },
            db_file = db_file
        }

        -- Execute assertion
        -- Assertion function returns (success, error_msg_or_nil)
        local ok, result, err_msg = pcall(assertion_fn, actual_doc, helpers)
        if not ok then
            return "failed", "Assertion error: " .. tostring(result)
        end

        -- Handle result: true = pass, false/string = fail
        if result == true then
            return "passed", nil
        elseif result == false then
            -- assert_ast_equal returns (false, error_message)
            return "failed", err_msg or "Assertion returned false"
        elseif type(result) == "string" then
            return "failed", result
        else
            return "failed", "Assertion returned unexpected type: " .. type(result)
        end
    else
        local match, err = compare_files(actual_path, expected_path, ext)
        if match then
            return "passed", nil
        else
            return "failed", err
        end
    end
end

local function run_suite(suite_dir, suite_name_override)
    local suite_name = suite_name_override or basename(suite_dir)
    local suite_yaml = suite_dir .. "/suite.yaml"

    if not file_exists(suite_yaml) then
        io.stderr:write("Warning: No suite.yaml in " .. suite_dir .. "\n")
        return
    end

    print("\nSuite: " .. suite_name)
    print(string.rep("-", 60))

    -- Start JUnit suite tracking
    if junit then
        junit.start_suite(suite_name)
    end

    -- Start coverage for this suite
    if coverage then
        local coverage_include = { "src/" }
        local model_name = suite_dir:match("models/([^/]+)/tests/?$")
        if not model_name then
            model_name = suite_dir:match("/models/([^/]+)/tests/?$")
        end
        if model_name then
            coverage_include = { "models/" .. model_name .. "/" }
        end

        coverage.start(suite_name, { include = coverage_include })
    end

    -- Find all .md files (test cases)
    local input_files = list_files(suite_dir, "*.md")

    for _, input_file in ipairs(input_files) do
        local test_name = basename(input_file, ".md")

        -- Apply test filter if specified
        if config.test and test_name ~= config.test then
            goto continue
        end

        local _, vc_id, _, vc_err = extract_vc_from_filename(test_name)

        -- Track test duration
        local start_time = os.clock()
        local status, message
        if vc_err then
            status = "failed"
            message = "VC naming convention violation: " .. vc_err
        else
            status, message = run_test(suite_dir, input_file)
        end
        local duration = os.clock() - start_time

        local report_name = test_name
        if vc_id then
            report_name = report_name .. " [" .. vc_id .. "]"
        end

        if status == "passed" then
            print("  ✓ " .. report_name)
            results.passed = results.passed + 1
        elseif status == "failed" then
            io.stderr:write("  ✗ " .. report_name .. ": " .. (message or "") .. "\n")
            results.failed = results.failed + 1
        else
            print("  ○ " .. report_name .. " (skipped: " .. (message or "") .. ")")
            results.skipped = results.skipped + 1
        end

        -- Record in JUnit
        if junit then
            junit.record_test(test_name, status, duration, message, nil, vc_id)
        end

        table.insert(results.tests, {
            suite = suite_name,
            name = test_name,
            vc_id = vc_id,
            status = status,
            message = message,
            duration = duration
        })

        ::continue::
    end

    -- Coverage continues accumulating (no-op stop)
    if coverage then
        coverage.stop()
    end

    -- End JUnit suite
    if junit then
        junit.end_suite()
    end
end

local function run_all_suites()
    -- Clean build directories before running tests
    clean_build_dirs()

    -- Standard e2e test suites
    local e2e_dir = "tests/e2e"
    local suites = list_dirs(e2e_dir)

    for _, suite_dir in ipairs(suites) do
        local suite_name = basename(suite_dir)

        -- Apply suite filter if specified
        if config.suite and suite_name ~= config.suite then
            goto continue
        end

        run_suite(suite_dir, suite_name)

        ::continue::
    end

    -- Model-defined test suites (models/{model}/tests/)
    local models_dir = speccompiler_home .. "/models"
    local model_dirs = list_dirs(models_dir)

    for _, model_dir in ipairs(model_dirs) do
        local model_tests_dir = model_dir .. "/tests"
        local suite_yaml = model_tests_dir .. "/suite.yaml"

        if file_exists(suite_yaml) then
            local suite_name = basename(model_dir) .. "-tests"

            -- Apply suite filter if specified
            if config.suite and suite_name ~= config.suite then
                goto model_continue
            end

            run_suite(model_tests_dir, suite_name)
        end

        ::model_continue::
    end
end

local function print_summary()
    print("\n" .. string.rep("=", 60))
    print(string.format("Results: %d passed, %d failed, %d skipped",
        results.passed, results.failed, results.skipped))
    print(string.rep("=", 60))
end

-- ============================================
-- Pandoc Filter Entry Point
-- ============================================

function Meta(meta)
    -- Extract configuration from metadata
    if meta.suite then
        config.suite = pandoc.utils.stringify(meta.suite)
    end
    if meta.test then
        config.test = pandoc.utils.stringify(meta.test)
    end
    if meta.coverage then
        config.coverage = true
    end
    if meta.junit then
        config.junit = true
    end
    if meta.report_dir then
        config.report_dir = pandoc.utils.stringify(meta.report_dir)
    end

    -- Initialize reporters if enabled
    if config.junit then
        local ok, j = pcall(require, "helpers.junit_reporter")
        if ok then
            junit = j
            junit.reset()
            junit.report_path = config.report_dir .. "/junit.xml"
            -- Load previous partial results (for multi-process accumulation
            -- when run.sh executes each suite in a separate pandoc process)
            local partial_path = config.report_dir .. "/junit.partial"
            junit.load_partial(partial_path)
            print("[junit] JUnit reporting enabled")
        else
            io.stderr:write("[junit] Warning: junit_reporter not available\n")
        end
    end

    if config.coverage then
        local ok, c = pcall(require, "helpers.coverage")
        if ok and c.is_available() then
            coverage = c
            coverage.report_dir = config.report_dir .. "/coverage"
            print("[coverage] Coverage reporting enabled")
        else
            io.stderr:write("[coverage] Warning: luacov not available, coverage disabled\n")
        end
    end

    -- Run tests
    print("\nSpecCompiler E2E Test Runner")
    print(string.rep("=", 60))

    run_all_suites()
    print_summary()

    -- Generate reports
    if junit then
        mkdir_p(config.report_dir)
        -- Save partial results for next suite's process to accumulate
        local partial_path = config.report_dir .. "/junit.partial"
        junit.write_partial(partial_path)
        if junit.write_report() then
            print("\n[junit] Report written to: " .. junit.report_path)
        end
    end

    if coverage then
        -- Finalize coverage collection
        coverage.finalize()

        -- Generate LCOV from accumulated stats (uses current_suite name)
        local suite_name = coverage.current_suite or "coverage"
        local lcov_file = coverage.generate_lcov(suite_name)
        if lcov_file then
            print("\n[coverage] " .. suite_name .. " report:")
            print("  LCOV: " .. lcov_file)

            -- Generate per-suite HTML report
            local html_dir = coverage.generate_html(suite_name)
            if html_dir then
                print("  HTML: " .. html_dir .. "/index.html")
            end
        else
            print("\n[coverage] Warning: No coverage data collected")
        end
    end

    -- Exit with appropriate code
    if results.failed > 0 then
        os.exit(1)
    else
        os.exit(0)
    end
end

return {{Meta = Meta}}
