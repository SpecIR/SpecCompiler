-- SpecCompiler Mutation Testing Engine
-- Pandoc filter that runs mutation testing on SQL proof views and Lua source.
-- Usage: pandoc --lua-filter tests/mutation/mutator.lua --metadata mode=sql < /dev/null
--
-- Modes:
--   sql           Run SQL proof view mutations (default + sw_docs models)
--   lua           Run Lua source mutations (requires target metadata)
--   all           Run both

local speccompiler_home = os.getenv("SPECCOMPILER_HOME") or "."
package.path = speccompiler_home .. "/src/?.lua;" ..
    speccompiler_home .. "/src/?/init.lua;" ..
    speccompiler_home .. "/?.lua;" ..
    speccompiler_home .. "/?/init.lua;" ..
    speccompiler_home .. "/tests/?.lua;" ..
    speccompiler_home .. "/tests/helpers/?.lua;" ..
    speccompiler_home .. "/tests/mutation/?.lua;" ..
    package.path

local json = require("dkjson")
local engine = require("core.engine")
local sql_operators = require("sql_operators")
local lua_operators = require("lua_operators")

-- ============================================
-- Configuration
-- ============================================

local config = {
    mode = "sql",
    target = nil,         -- Lua mutation target file
    verbose = false,
    report_dir = "tests/reports/mutation",
    timeout = 30,         -- seconds per mutant (wall clock estimate)
}

-- ============================================
-- File system helpers
-- ============================================

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true end
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

local function basename(path, ext)
    local name = path:match("([^/]+)$")
    if ext and name:sub(-#ext) == ext then
        name = name:sub(1, -#ext - 1)
    end
    return name
end

-- Simple YAML parser (same as runner.lua)
local function parse_yaml(content)
    local result = {}
    local current_table = result
    local indent_stack = {{t = result, indent = -1}}
    for line in content:gmatch("[^\n]+") do
        local indent = #(line:match("^(%s*)") or "")
        local key, value = line:match("^%s*([%w_]+):%s*(.*)$")
        if key then
            while #indent_stack > 1 and indent_stack[#indent_stack].indent >= indent do
                table.remove(indent_stack)
            end
            current_table = indent_stack[#indent_stack].t
            if value == "" then
                current_table[key] = {}
                table.insert(indent_stack, {t = current_table[key], indent = indent})
            else
                current_table[key] = value
            end
        end
    end
    return result
end

-- ============================================
-- Module cache management
-- ============================================

---Clear all proof-related modules from package.loaded (forces re-require).
---@param model_name string e.g., "default" or "sw_docs"
local function clear_proof_modules(model_name)
    local prefix = "models." .. model_name .. ".proofs."
    for module_name, _ in pairs(package.loaded) do
        if module_name:sub(1, #prefix) == prefix then
            package.loaded[module_name] = nil
        end
    end
end

---Clear a specific Lua module from package.loaded.
---@param file_path string Source file path relative to project root (e.g., "src/pipeline/shared/render_utils.lua")
local function clear_source_module(file_path)
    -- Convert file path to require path: src/foo/bar.lua → foo.bar
    local mod_path = file_path
        :gsub("^src/", "")
        :gsub("%.lua$", "")
        :gsub("/", ".")
    package.loaded[mod_path] = nil

    -- Also try with src. prefix (some modules load both ways)
    local full_path = file_path:gsub("%.lua$", ""):gsub("/", ".")
    package.loaded[full_path] = nil
end

-- ============================================
-- SQL Proof Mutation Engine
-- ============================================

-- Resolve tmpdir for mutation DB files (avoids ZFS CoW pressure)
local mutation_db_dir
do
    local tmpdir = os.getenv("SPECCOMPILER_TEST_DB_DIR")
        or os.getenv("TMPDIR") or os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    mutation_db_dir = tmpdir .. "/speccompiler_mutation_dbs"
    os.execute("mkdir -p " .. mutation_db_dir)
end

---Build a project_info structure for running a specific verify test.
---@param suite_dir string Path to the test suite directory
---@param test_file string Test .md file name (basename)
---@return table project_info
local function build_test_project(suite_dir, test_file)
    local build_dir = suite_dir .. "/build/mutation"
    local test_name = test_file:gsub("%.md$", "")
    local db_file = mutation_db_dir .. "/" .. test_name .. ".db"
    local suite_config = parse_yaml(read_file(suite_dir .. "/suite.yaml") or "")

    mkdir_p(build_dir)

    -- Clean stale output to defeat incremental cache (each mutant must reprocess)
    os.remove(build_dir .. "/" .. test_name .. ".json")

    -- Clean stale DB files
    os.remove(db_file)
    os.remove(db_file .. "-wal")
    os.remove(db_file .. "-shm")
    os.remove(db_file .. "-journal")

    return {
        project = {
            code = (suite_config.project and suite_config.project.code) or "MUTATION",
            name = (suite_config.project and suite_config.project.name) or "Mutation Test"
        },
        template = suite_config.template or "default",
        files = { suite_dir .. "/" .. test_file },
        output_dir = build_dir,
        output_format = "json",
        outputs = {
            { format = "json", path = build_dir .. "/" .. test_file:gsub("%.md$", ".json") }
        },
        db_file = db_file,
        logging = { level = "ERROR" },
        validation = suite_config.validation,
    }, suite_config
end

---Shallow-clone a table (one level deep).
local function shallow_clone(t)
    local copy = {}
    for k, v in pairs(t) do copy[k] = v end
    return copy
end

---Collect the set of policy_key codes from diagnostics.
---@param diag table|nil Diagnostics object
---@return table Set of policy_key codes {code=true}
local function collect_diagnostic_codes(diag)
    local codes = {}
    if not diag then return codes end
    for _, e in ipairs(diag.errors or {}) do
        if e.code then codes[e.code] = (codes[e.code] or 0) + 1 end
    end
    for _, w in ipairs(diag.warnings or {}) do
        if w.code then codes[w.code] = (codes[w.code] or 0) + 1 end
    end
    return codes
end

---Run all SQL proof view mutations.
---@return table report {total, killed, survived, skipped, views={...}}
local function run_sql_mutations()
    print("\nSQL Proof Mutations")
    print(string.rep("=", 60))

    -- Discover which models have SQL proof definitions
    local model_sql_modules = {
        { model = "default", require_path = "models.default.proofs.sql" },
        { model = "sw_docs", require_path = "models.sw_docs.proofs.sql" },
    }

    -- Ensure pristine module state: clear any stale proof modules from
    -- previous runs (e.g., if run.sh invokes mutator after the normal suite).
    for _, msm in ipairs(model_sql_modules) do
        clear_proof_modules(msm.model)
    end

    -- Load original SQL modules fresh from disk
    for _, msm in ipairs(model_sql_modules) do
        local ok, mod = pcall(require, msm.require_path)
        if ok then
            msm.sql_module = mod
        end
    end

    -- Find test suites that exercise proofs (expect_errors mode)
    local verify_suite = speccompiler_home .. "/tests/e2e/verify"
    local casting_neg_suite = speccompiler_home .. "/tests/e2e/casting_negative"

    -- Clean mutation build dirs upfront to defeat incremental cache from prior runs
    os.execute("rm -rf " .. verify_suite .. "/build/mutation")
    os.execute("rm -rf " .. casting_neg_suite .. "/build/mutation")

    -- Build baseline: run each verify test once to get expected diagnostic codes
    local baseline_codes = {}  -- test_file → {code = count}
    local test_files = {}

    local function discover_md_files(dir)
        local files = {}
        local handle = io.popen("find " .. dir .. " -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort")
        if handle then
            for line in handle:lines() do
                table.insert(files, basename(line))
            end
            handle:close()
        end
        return files
    end

    -- Collect verify suite test files
    for _, f in ipairs(discover_md_files(verify_suite)) do
        table.insert(test_files, { suite = verify_suite, file = f })
    end
    -- Collect casting_negative test files
    if file_exists(casting_neg_suite .. "/suite.yaml") then
        for _, f in ipairs(discover_md_files(casting_neg_suite)) do
            table.insert(test_files, { suite = casting_neg_suite, file = f })
        end
    end

    print(string.format("\n  Establishing baseline (%d test files)...", #test_files))
    for _, tf in ipairs(test_files) do
        local project_info = build_test_project(tf.suite, tf.file)
        local ok, diag_or_err = pcall(function()
            return engine.run_project(project_info)
        end)
        if ok and diag_or_err then
            baseline_codes[tf.file] = collect_diagnostic_codes(diag_or_err)
        else
            baseline_codes[tf.file] = {}
        end
    end

    -- Now run mutations
    local report = {
        total = 0,
        killed = 0,
        survived = 0,
        skipped = 0,
        views = {},
    }

    for _, msm in ipairs(model_sql_modules) do
        if not msm.sql_module then goto next_model end

        local orig_sql_module = msm.sql_module

        for view_name, view_sql in pairs(orig_sql_module) do
            if type(view_sql) ~= "string" then goto next_view end

            local mutations = sql_operators.generate_mutations(view_name, view_sql)
            if #mutations == 0 then goto next_view end

            local view_report = {
                mutations = #mutations,
                killed = 0,
                survived = 0,
                skipped = 0,
                survivors = {},
            }

            print(string.format("\n  %s (%d mutations)", view_name, #mutations))

            for _, mutation in ipairs(mutations) do
                report.total = report.total + 1

                -- 1. Create mutated SQL module clone
                local mutated_sql = shallow_clone(orig_sql_module)
                mutated_sql[view_name] = mutation.sql

                -- 2. Clear proof module cache, then inject mutated SQL.
                -- Order matters: clear_proof_modules removes ALL models.X.proofs.*
                -- entries (including the sql module), so inject AFTER clearing.
                clear_proof_modules(msm.model)
                package.loaded[msm.require_path] = mutated_sql

                -- 3. Run each test file and compare diagnostics to baseline
                local mutant_killed = false
                for _, tf in ipairs(test_files) do
                    local project_info = build_test_project(tf.suite, tf.file)
                    local ok, diag_or_err = pcall(function()
                        return engine.run_project(project_info)
                    end)

                    if not ok then
                        -- Pipeline crash = mutant killed (crash is detectable)
                        mutant_killed = true
                        break
                    end

                    local mutant_codes = collect_diagnostic_codes(diag_or_err)
                    local baseline = baseline_codes[tf.file] or {}

                    -- Compare: if diagnostic codes differ, mutant is killed
                    -- Check baseline codes missing in mutant
                    for code, count in pairs(baseline) do
                        if not mutant_codes[code] or mutant_codes[code] ~= count then
                            mutant_killed = true
                            break
                        end
                    end
                    if mutant_killed then break end

                    -- Check mutant codes not in baseline
                    for code, count in pairs(mutant_codes) do
                        if not baseline[code] or baseline[code] ~= count then
                            mutant_killed = true
                            break
                        end
                    end
                    if mutant_killed then break end
                end

                -- 4. Restore original (clear first, then set — same order as inject)
                clear_proof_modules(msm.model)
                package.loaded[msm.require_path] = orig_sql_module

                -- 5. Record result
                if mutant_killed then
                    report.killed = report.killed + 1
                    view_report.killed = view_report.killed + 1
                    if config.verbose then
                        print(string.format("    ✓ killed    %s: %s", mutation.operator, mutation.desc))
                    end
                else
                    report.survived = report.survived + 1
                    view_report.survived = view_report.survived + 1
                    print(string.format("    ✗ SURVIVED  %s: %s", mutation.operator, mutation.desc))
                    table.insert(view_report.survivors, {
                        operator = mutation.operator,
                        desc = mutation.desc,
                        position = mutation.position,
                    })
                end
            end

            local score = view_report.mutations > 0
                and (view_report.killed / view_report.mutations * 100) or 0
            print(string.format("  Score: %d/%d killed (%.1f%%)",
                view_report.killed, view_report.mutations, score))
            report.views[view_name] = view_report

            ::next_view::
        end

        ::next_model::
    end

    -- Summary
    print(string.rep("=", 60))
    local total_score = report.total > 0
        and (report.killed / report.total * 100) or 0
    print(string.format("TOTAL SQL: %d/%d killed (%.1f%%), %d survived, %d skipped",
        report.killed, report.total, total_score,
        report.survived, report.skipped))

    return report
end

-- ============================================
-- Lua Source Mutation Engine
-- ============================================

---Compute a simple hash of a file's contents for content comparison.
---Uses DJB2 hash — fast, sufficient for change detection (not crypto).
---@param path string File path
---@return string|nil hash Hex hash string, or nil if file doesn't exist
local function file_content_hash(path)
    local content = read_file(path)
    if not content then return nil end
    local h = 5381
    for i = 1, #content do
        h = ((h * 33) + content:byte(i)) % 0x100000000
    end
    return string.format("%08x", h)
end

---Capture a full test fingerprint: pass/fail + diagnostics + output hash.
---Any change in any signal means the mutation was detected.
---@param suite_dir string
---@param test_file string
---@return table fingerprint {ok, codes, output_hash}
local function capture_test_fingerprint(suite_dir, test_file)
    local project_info = build_test_project(suite_dir, test_file)
    local ok, diag_or_err = pcall(function()
        return engine.run_project(project_info)
    end)

    local codes = {}
    if ok and diag_or_err then
        codes = collect_diagnostic_codes(diag_or_err)
    end

    local output_path = project_info.outputs[1].path
    local output_hash = file_content_hash(output_path)

    return {
        ok = ok,
        codes = codes,
        output_hash = output_hash,
    }
end

---Compare two fingerprints. Returns true if they differ (mutant killed).
---@param baseline table
---@param mutant table
---@return boolean killed
---@return string|nil reason What differed
local function fingerprints_differ(baseline, mutant)
    -- Signal 1: pass/fail status
    if baseline.ok ~= mutant.ok then
        return true, "status"
    end
    -- Signal 2: diagnostic codes
    for code, count in pairs(baseline.codes) do
        if not mutant.codes[code] or mutant.codes[code] ~= count then
            return true, "diagnostics"
        end
    end
    for code, count in pairs(mutant.codes) do
        if not baseline.codes[code] or baseline.codes[code] ~= count then
            return true, "diagnostics"
        end
    end
    -- Signal 3: output content
    if baseline.output_hash ~= mutant.output_hash then
        return true, "output"
    end
    return false, nil
end

---Discover all test files in a suite directory.
---@param suite_dir string
---@return table files Array of basenames
local function discover_suite_tests(suite_dir)
    local files = {}
    local handle = io.popen("find " .. suite_dir .. " -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort")
    if handle then
        for line in handle:lines() do
            table.insert(files, basename(line))
        end
        handle:close()
    end
    return files
end

---Run mutations on a single Lua source file.
---@param target_path string Path to the Lua source file (relative to project root)
---@param suites table|nil Array of {suite=path, file=md_name} to run (default: all E2E)
---@return table report
local function run_lua_mutations(target_path, suites)
    print(string.format("\nLua Source Mutations: %s", target_path))
    print(string.rep("=", 60))

    local abs_path = speccompiler_home .. "/" .. target_path
    local original = read_file(abs_path)
    if not original then
        print("  ERROR: Cannot read " .. abs_path)
        return { total = 0, killed = 0, survived = 0, skipped = 0 }
    end

    -- Split into lines
    local lines = {}
    for line in (original .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end

    -- If no suites specified, discover from all E2E suites (all test files, not just first)
    if not suites then
        suites = {}
        local e2e_dir = speccompiler_home .. "/tests/e2e"
        local handle = io.popen("find " .. e2e_dir .. " -maxdepth 1 -type d 2>/dev/null | sort")
        if handle then
            for dir in handle:lines() do
                if dir ~= e2e_dir and file_exists(dir .. "/suite.yaml") then
                    local suite_config = parse_yaml(read_file(dir .. "/suite.yaml") or "")
                    -- Skip expect_errors suites (they test proofs, not source logic)
                    if suite_config.expect_errors ~= "true" then
                        for _, md_file in ipairs(discover_suite_tests(dir)) do
                            table.insert(suites, { suite = dir, file = md_file })
                        end
                    end
                end
            end
            handle:close()
        end
    end

    -- Clean mutation build dirs for all suites upfront
    local cleaned_dirs = {}
    for _, tf in ipairs(suites) do
        local mutation_dir = tf.suite .. "/build/mutation"
        if not cleaned_dirs[mutation_dir] then
            os.execute("rm -rf " .. mutation_dir)
            cleaned_dirs[mutation_dir] = true
        end
    end

    -- Establish baseline: run each test and capture full fingerprint
    print(string.format("  Establishing baseline (%d tests)...", #suites))
    local baselines = {}  -- test_key → fingerprint
    for _, tf in ipairs(suites) do
        local key = tf.suite .. "/" .. tf.file
        baselines[key] = capture_test_fingerprint(tf.suite, tf.file)
    end

    -- Generate all mutations
    local all_mutations = {}
    for i, line in ipairs(lines) do
        local line_mutations = lua_operators.generate_mutations(line, i)
        for _, m in ipairs(line_mutations) do
            table.insert(all_mutations, m)
        end
    end

    -- Validate mutations with load()
    local valid_mutations = {}
    for _, m in ipairs(all_mutations) do
        local mutated_lines = {}
        for i, line in ipairs(lines) do
            if i == m.line_num then
                table.insert(mutated_lines, m.line)
            else
                table.insert(mutated_lines, line)
            end
        end
        local mutated_source = table.concat(mutated_lines, "\n")
        local fn, _ = load(mutated_source, "=mutant")
        if fn then
            m._source = mutated_source
            table.insert(valid_mutations, m)
        end
    end

    print(string.format("  %d mutations generated, %d valid (%.0f%% skip rate)",
        #all_mutations, #valid_mutations,
        #all_mutations > 0 and ((#all_mutations - #valid_mutations) / #all_mutations * 100) or 0))

    -- Run each valid mutation
    local report = {
        total = #valid_mutations,
        killed = 0,
        survived = 0,
        skipped = 0,
        survivors = {},
        kill_reasons = { status = 0, diagnostics = 0, output = 0 },
    }

    for idx, m in ipairs(valid_mutations) do
        -- 1. Write mutated source and clear module cache
        write_file(abs_path, m._source)
        clear_source_module(target_path)

        -- 2. Run tests and compare fingerprints
        local mutant_killed = false
        local kill_reason = nil
        for _, tf in ipairs(suites) do
            local key = tf.suite .. "/" .. tf.file
            local mutant_fp = capture_test_fingerprint(tf.suite, tf.file)
            local killed, reason = fingerprints_differ(baselines[key], mutant_fp)
            if killed then
                mutant_killed = true
                kill_reason = reason
                break
            end
        end

        -- 3. Record result
        if mutant_killed then
            report.killed = report.killed + 1
            report.kill_reasons[kill_reason] = (report.kill_reasons[kill_reason] or 0) + 1
            if config.verbose then
                print(string.format("    ✓ killed    L%d %s: %s [%s]",
                    m.line_num, m.operator, m.desc, kill_reason))
            end
        else
            report.survived = report.survived + 1
            print(string.format("    ✗ SURVIVED  L%d %s: %s",
                m.line_num, m.operator, m.desc))
            table.insert(report.survivors, {
                line_num = m.line_num,
                operator = m.operator,
                desc = m.desc,
                original_line = lines[m.line_num],
                mutated_line = m.line,
            })
        end

        -- Progress indicator for long runs
        if idx % 10 == 0 then
            io.stderr:write(string.format("\r  Progress: %d/%d mutations tested...", idx, #valid_mutations))
            io.stderr:flush()
        end
    end

    -- 4. Restore original (CRITICAL — always restore)
    write_file(abs_path, original)
    clear_source_module(target_path)

    if #valid_mutations > 20 then
        io.stderr:write("\r" .. string.rep(" ", 60) .. "\r")
    end

    -- Summary
    local score = report.total > 0
        and (report.killed / report.total * 100) or 0
    print(string.format("\n  Score: %d/%d killed (%.1f%%), %d survived",
        report.killed, report.total, score, report.survived))
    if report.killed > 0 then
        local kr = report.kill_reasons
        print(string.format("  Kill signals: output=%d, diagnostics=%d, status=%d",
            kr.output or 0, kr.diagnostics or 0, kr.status or 0))
    end

    return report
end

-- ============================================
-- Report Writer
-- ============================================

local function write_json_report(report, filename)
    mkdir_p(config.report_dir)
    local path = config.report_dir .. "/" .. filename
    report.timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local content = json.encode(report, { indent = true })
    write_file(path, content)
    print(string.format("\n  Report written to: %s", path))
end

-- ============================================
-- Entry Point (Pandoc filter)
-- ============================================

function Meta(meta)
    if meta.mode then
        config.mode = pandoc.utils.stringify(meta.mode)
    end
    if meta.target then
        config.target = pandoc.utils.stringify(meta.target)
    end
    if meta.verbose and pandoc.utils.stringify(meta.verbose) == "true" then
        config.verbose = true
    end

    print("SpecCompiler Mutation Testing Engine")
    print(string.rep("=", 60))
    print(string.format("Mode: %s", config.mode))
    if config.target then
        print(string.format("Target: %s", config.target))
    end

    local sql_report, lua_report
    local run_start = os.clock()

    if config.mode == "sql" or config.mode == "all" then
        local t0 = os.clock()
        sql_report = run_sql_mutations()
        sql_report.duration_seconds = math.floor(os.clock() - t0)
        write_json_report(sql_report, "sql_report.json")
    end

    if config.mode == "lua" or config.mode == "all" then
        if not config.target then
            if config.mode == "lua" then
                print("\nERROR: --metadata target=<file> required for Lua mutation mode")
                return  -- Don't os.exit — let Pandoc clean up normally
            end
            -- --all without target: skip Lua, just report SQL
            print("\n  (Skipping Lua mutations: no --lua target specified)")
        else
            local t0 = os.clock()
            lua_report = run_lua_mutations(config.target)
            lua_report.duration_seconds = math.floor(os.clock() - t0)
            write_json_report(lua_report, "lua_report.json")
        end
    end

    -- Overall summary
    print(string.format("\n%s", string.rep("=", 60)))
    print("MUTATION TESTING COMPLETE")
    if sql_report then
        local s = sql_report.total > 0 and (sql_report.killed / sql_report.total * 100) or 0
        print(string.format("  SQL:  %d/%d killed (%.1f%%)", sql_report.killed, sql_report.total, s))
    end
    if lua_report then
        local s = lua_report.total > 0 and (lua_report.killed / lua_report.total * 100) or 0
        print(string.format("  Lua:  %d/%d killed (%.1f%%)", lua_report.killed, lua_report.total, s))
    end
end

return {{Meta = Meta}}
