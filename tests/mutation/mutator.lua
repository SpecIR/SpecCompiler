-- SpecCompiler Mutation Testing Engine
-- Pandoc filter that runs mutation testing on SQL verification views and Lua source.
-- Usage: pandoc --lua-filter tests/mutation/mutator.lua --metadata mode=sql < /dev/null
--
-- Modes:
--   sql           Run SQL verification view mutations (default + sw_docs models)
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
    report_dir = os.getenv("MUTATION_REPORT_DIR") or "tests/reports/mutation",
    equivalents_file = "tests/mutation/sql_equivalents.lua",
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

---Clear all verification-view-related modules from package.loaded (forces re-require).
---@param model_name string e.g., "default" or "sw_docs"
local function clear_analyze_query_modules(model_name)
    local prefix = "models." .. model_name .. ".analyze_queries."
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
-- SQL Verification View Mutation Engine
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

    -- Clean cached external renders. A failed render can leave an output file
    -- behind (PlantUML draws its error), and the render handler treats an
    -- existing output as a cache hit, so a run after the first would resolve a
    -- float that the first run reported as failed. Every run must be cold.
    if not os.getenv("MUTATION_KEEP_RENDER_CACHE") then
        os.execute("rm -rf " .. build_dir .. "/diagrams")
    end

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

---Collect the set of policy_key codes from diagnostics (used by Lua mode).
---@param diag table|nil Diagnostics object
---@return table Set of policy_key codes {code=count}
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

---Collect a diagnostic signature for the SQL oracle.
---`codes` is the per-policy_key count (reporting); `locs` is the multiset of
---(policy_key, file, line) triples that the oracle compares; `failed` marks
---policy_keys whose analyze query itself failed to execute (invalid SQL).
---@param diag table|nil Diagnostics object
---@return table signature {codes={}, locs={}, failed={}}
local function collect_diagnostic_signature(diag)
    local sig = { codes = {}, locs = {}, failed = {} }
    if not diag then return sig end
    local function add(e)
        if not e.code then return end
        sig.codes[e.code] = (sig.codes[e.code] or 0) + 1
        local key = e.code .. "|" .. tostring(e.file) .. "|" .. tostring(e.line)
        sig.locs[key] = (sig.locs[key] or 0) + 1
        if e.message and e.message:find("Validation query failed", 1, true) then
            sig.failed[e.code] = true
        end
    end
    for _, e in ipairs(diag.errors or {}) do add(e) end
    for _, w in ipairs(diag.warnings or {}) do add(w) end
    return sig
end

---Diff two location multisets, ignoring codes flagged as unstable.
---@return table[] diffs Array of {key, base, mutant}
local function diff_locs(base, mut, unstable)
    local diffs = {}
    local function code_of(key) return key:match("^([^|]*)") end
    for key, count in pairs(base) do
        if not unstable[code_of(key)] and (mut[key] or 0) ~= count then
            table.insert(diffs, { key = key, base = count, mutant = mut[key] or 0 })
        end
    end
    for key, count in pairs(mut) do
        if not unstable[code_of(key)] and base[key] == nil then
            table.insert(diffs, { key = key, base = 0, mutant = count })
        end
    end
    table.sort(diffs, function(a, b) return a.key < b.key end)
    return diffs
end

---Load the annotated equivalent-mutant catalogue (tests/mutation/sql_equivalents.lua).
---Each entry is {view=, operator=, desc=, reason=}; a surviving mutant matching
---(view, operator, desc) is reported as "equivalent" and removed from the score
---denominator. The catalogue never affects killed mutants.
---@return table index keyed by view.."\0"..operator.."\0"..desc
local function load_equivalents()
    local path = speccompiler_home .. "/" .. config.equivalents_file
    if not file_exists(path) then return {} end
    local ok, list = pcall(dofile, path)
    if not ok or type(list) ~= "table" then
        print("  WARNING: could not load " .. path .. ": " .. tostring(list))
        return {}
    end
    local index = {}
    for _, e in ipairs(list) do
        -- Entries may carry `position` (byte offset of the mutation site) to
        -- distinguish same-description mutants, e.g. one per UNION branch.
        local key = e.view .. "\0" .. e.operator .. "\0" .. e.desc
        if e.position then key = key .. "\0" .. tostring(e.position) end
        index[key] = e
    end
    return index
end

---Find the equivalence entry for a mutant: position-specific first, then generic.
local function find_equivalent(index, view, mutation)
    local key = view .. "\0" .. mutation.operator .. "\0" .. mutation.desc
    return index[key .. "\0" .. tostring(mutation.position)] or index[key]
end

local function sorted_keys(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    return keys
end

---Run all SQL verification view mutations.
---@return table report
local function run_sql_mutations()
    print("\nSQL Verification View Mutations")
    print(string.rep("=", 60))

    -- Discover which models have SQL verification view definitions
    local model_sql_modules = {
        { model = "default", require_path = "models.default.analyze_queries.sql" },
        { model = "sw_docs", require_path = "models.sw_docs.analyze_queries.sql" },
    }

    -- Ensure pristine module state: clear any stale verification view modules from
    -- previous runs (e.g., if run.sh invokes mutator after the normal suite).
    for _, msm in ipairs(model_sql_modules) do
        clear_analyze_query_modules(msm.model)
    end

    -- Load original SQL modules fresh from disk
    for _, msm in ipairs(model_sql_modules) do
        local ok, mod = pcall(require, msm.require_path)
        if ok then
            msm.sql_module = mod
        end
    end

    -- Find test suites that exercise analyze_queries (expect_errors mode)
    local verify_suite = speccompiler_home .. "/tests/e2e/verify"
    local casting_neg_suite = speccompiler_home .. "/tests/e2e/casting_negative"

    -- Clean mutation build dirs upfront to defeat incremental cache from prior runs
    os.execute("rm -rf " .. verify_suite .. "/build/mutation")
    os.execute("rm -rf " .. casting_neg_suite .. "/build/mutation")

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

    -- Baseline: run every fixture twice and keep the second signature. The first
    -- pass warms caches that persist across runs inside build/mutation (external
    -- renders, for instance), so that the baseline is taken under the same
    -- conditions as every mutant run. Any policy_key whose count differs between
    -- the two passes is unstable and is excluded from the oracle.
    print(string.format("\n  Establishing baseline (%d test files, 2 passes)...", #test_files))
    local baseline = {}        -- test_file -> signature
    local first_pass = {}      -- test_file -> signature (pass 1)
    local unstable_codes = {}  -- test_file -> { code -> true }
    local unstable_detail = {} -- test_file -> { code = {pass1=n, pass2=n} }
    for pass = 1, 2 do
        for _, tf in ipairs(test_files) do
            local project_info = build_test_project(tf.suite, tf.file)
            local ok, diag_or_err = pcall(function()
                return engine.run_project(project_info)
            end)
            local sig = collect_diagnostic_signature(ok and diag_or_err or nil)
            if pass == 1 then first_pass[tf.file] = sig else baseline[tf.file] = sig end
        end
    end
    for _, tf in ipairs(test_files) do
        local c1, c2 = first_pass[tf.file].codes, baseline[tf.file].codes
        for code in pairs(c1) do
            if c1[code] ~= c2[code] then
                unstable_codes[tf.file] = unstable_codes[tf.file] or {}
                unstable_codes[tf.file][code] = true
                unstable_detail[tf.file] = unstable_detail[tf.file] or {}
                unstable_detail[tf.file][code] = { pass1 = c1[code], pass2 = c2[code] or 0 }
            end
        end
        for code in pairs(c2) do
            if c1[code] == nil then
                unstable_codes[tf.file] = unstable_codes[tf.file] or {}
                unstable_codes[tf.file][code] = true
                unstable_detail[tf.file] = unstable_detail[tf.file] or {}
                unstable_detail[tf.file][code] = { pass1 = 0, pass2 = c2[code] }
            end
        end
    end
    for _, f in ipairs(sorted_keys(unstable_detail)) do
        for _, code in ipairs(sorted_keys(unstable_detail[f])) do
            local d = unstable_detail[f][code]
            print(string.format("  ! unstable baseline %s: %s pass1=%d pass2=%d (excluded from oracle)",
                f, code, d.pass1, d.pass2))
        end
    end

    local equivalents = load_equivalents()

    local report = {
        total = 0,        -- unique, valid mutants (denominator before equivalents)
        killed = 0,
        survived = 0,     -- unclassified survivors
        equivalent = 0,   -- survivors listed in sql_equivalents.lua
        stillborn = 0,    -- mutants whose SQL does not execute (excluded from total)
        duplicates = 0,   -- identical SQL generated by two operators (excluded)
        score = 0,        -- killed / (total - equivalent)
        kill_reasons = { crash = 0, diagnostics = 0 },
        equivalent_by_category = {},   -- category -> count (from sql_equivalents.lua)
        dead_views = {},               -- views with no kill and no survivor: every mutant equivalent
        unstable_codes = unstable_codes,
        unstable_detail = unstable_detail,
        baseline = {},
        test_files = {},
        per_operator = {},
        per_view = {},
        views = {},
        survivors = {},
        equivalents = {},
        stillborns = {},
        duplicate_list = {},
        kills = {},
    }
    for _, tf in ipairs(test_files) do
        table.insert(report.test_files, tf.file)
        report.baseline[tf.file] = baseline[tf.file].codes
    end

    local function bump(tbl, key, field)
        tbl[key] = tbl[key] or { total = 0, killed = 0, survived = 0, equivalent = 0, stillborn = 0 }
        tbl[key][field] = tbl[key][field] + 1
    end

    for _, msm in ipairs(model_sql_modules) do
        if not msm.sql_module then goto next_model end

        local orig_sql_module = msm.sql_module
        local view_names = {}
        for view_name, view_sql in pairs(orig_sql_module) do
            if type(view_sql) == "string" then table.insert(view_names, view_name) end
        end
        table.sort(view_names)

        for _, view_name in ipairs(view_names) do
            local view_sql = orig_sql_module[view_name]
            local generated = sql_operators.generate_mutations(view_name, view_sql)
            if #generated == 0 then goto next_view end

            -- Drop duplicates: two operators can produce the same mutant text
            -- (e.g. "> N" -> ">= N" from flip_comparison and change_aggregate).
            local mutations, seen_sql = {}, {}
            for _, m in ipairs(generated) do
                if seen_sql[m.sql] then
                    report.duplicates = report.duplicates + 1
                    table.insert(report.duplicate_list, {
                        view = view_name, operator = m.operator, desc = m.desc, same_as = seen_sql[m.sql]
                    })
                else
                    seen_sql[m.sql] = m.operator .. ": " .. m.desc
                    table.insert(mutations, m)
                end
            end

            local view_report = {
                mutations = #mutations,
                killed = 0,
                survived = 0,
                equivalent = 0,
                stillborn = 0,
                survivors = {},
            }

            print(string.format("\n  %s (%d mutations)", view_name, #mutations))

            for _, mutation in ipairs(mutations) do
                -- 1. Create mutated SQL module clone
                local mutated_sql = shallow_clone(orig_sql_module)
                mutated_sql[view_name] = mutation.sql

                -- 2. Clear analyze_query module cache, then inject mutated SQL.
                -- Order matters: clear_analyze_query_modules removes ALL models.X.analyze_queries.*
                -- entries (including the sql module), so inject AFTER clearing.
                clear_analyze_query_modules(msm.model)
                package.loaded[msm.require_path] = mutated_sql

                -- 3. Run each test file and compare diagnostics to baseline.
                -- Stops at the first fixture that distinguishes the mutant.
                local status, killed_by, reason, diffs, err = "survived", nil, nil, nil, nil
                for _, tf in ipairs(test_files) do
                    local project_info = build_test_project(tf.suite, tf.file)
                    local ok, diag_or_err = pcall(function()
                        return engine.run_project(project_info)
                    end)

                    if not ok then
                        err = tostring(diag_or_err)
                        if err:find("Failed to execute SQL", 1, true) then
                            -- The mutant is not a valid view definition: it cannot
                            -- be exercised by the oracle and is excluded from the score.
                            status = "stillborn"
                        else
                            status, reason = "killed", "crash"
                        end
                        killed_by = tf.file
                        break
                    end

                    local sig = collect_diagnostic_signature(diag_or_err)
                    if next(sig.failed) then
                        status, killed_by = "stillborn", tf.file
                        err = "analyze query failed at execution"
                        break
                    end
                    local d = diff_locs(baseline[tf.file].locs, sig.locs, unstable_codes[tf.file] or {})
                    if #d > 0 then
                        status, reason, killed_by, diffs = "killed", "diagnostics", tf.file, d
                        break
                    end
                end

                -- 4. Restore original (clear first, then set — same order as inject)
                clear_analyze_query_modules(msm.model)
                package.loaded[msm.require_path] = orig_sql_module

                -- 5. Record result
                local record = {
                    model = msm.model,
                    view = view_name,
                    operator = mutation.operator,
                    desc = mutation.desc,
                    position = mutation.position,
                }
                if status == "stillborn" then
                    report.stillborn = report.stillborn + 1
                    view_report.stillborn = view_report.stillborn + 1
                    bump(report.per_operator, mutation.operator, "stillborn")
                    record.error = err
                    table.insert(report.stillborns, record)
                    print(string.format("    - stillborn %s: %s (%s)", mutation.operator, mutation.desc,
                        tostring(err):sub(1, 80)))
                    goto next_mutation
                end

                report.total = report.total + 1
                bump(report.per_operator, mutation.operator, "total")

                if status == "killed" then
                    report.killed = report.killed + 1
                    view_report.killed = view_report.killed + 1
                    bump(report.per_operator, mutation.operator, "killed")
                    report.kill_reasons[reason] = (report.kill_reasons[reason] or 0) + 1
                    record.killed_by = killed_by
                    record.reason = reason
                    record.diffs = diffs
                    record.error = err
                    table.insert(report.kills, record)
                    if config.verbose then
                        print(string.format("    ✓ killed[%s]  %s: %s  <- %s", reason,
                            mutation.operator, mutation.desc, killed_by))
                    end
                else
                    local eq = find_equivalent(equivalents, view_name, mutation)
                    record.sql = mutation.sql
                    if eq then
                        report.equivalent = report.equivalent + 1
                        view_report.equivalent = view_report.equivalent + 1
                        bump(report.per_operator, mutation.operator, "equivalent")
                        local cat = eq.category or "unclassified"
                        report.equivalent_by_category[cat] = (report.equivalent_by_category[cat] or 0) + 1
                        local po = report.per_operator[mutation.operator]
                        po.equivalent_by_category = po.equivalent_by_category or {}
                        po.equivalent_by_category[cat] = (po.equivalent_by_category[cat] or 0) + 1
                        record.reason = eq.reason
                        record.category = eq.category
                        table.insert(report.equivalents, record)
                        print(string.format("    = equivalent %s: %s", mutation.operator, mutation.desc))
                    else
                        report.survived = report.survived + 1
                        view_report.survived = view_report.survived + 1
                        bump(report.per_operator, mutation.operator, "survived")
                        table.insert(report.survivors, record)
                        table.insert(view_report.survivors, {
                            operator = mutation.operator,
                            desc = mutation.desc,
                            position = mutation.position,
                        })
                        print(string.format("    ✗ SURVIVED  %s: %s", mutation.operator, mutation.desc))
                    end
                end
                ::next_mutation::
            end

            local denom = view_report.mutations - view_report.equivalent - view_report.stillborn
            local score = denom > 0 and (view_report.killed / denom * 100) or 0
            print(string.format("  Score: %d/%d killed (%.1f%%)%s%s",
                view_report.killed, denom, score,
                view_report.equivalent > 0 and string.format(", %d equivalent", view_report.equivalent) or "",
                view_report.stillborn > 0 and string.format(", %d stillborn", view_report.stillborn) or ""))
            report.views[view_name] = view_report
            report.per_view[view_name] = {
                total = view_report.mutations - view_report.stillborn,
                killed = view_report.killed,
                survived = view_report.survived,
                equivalent = view_report.equivalent,
                stillborn = view_report.stillborn,
            }
            if view_report.killed == 0 and view_report.survived == 0 and view_report.equivalent > 0 then
                table.insert(report.dead_views, view_name)
                print("  ! every mutant of this view is equivalent: the query is unreachable with the shipped models")
            end

            ::next_view::
        end

        ::next_model::
    end

    -- Summary
    local denom = report.total - report.equivalent
    report.score = denom > 0 and (report.killed / denom * 100) or 0
    print(string.rep("=", 60))
    print(string.format("%-18s %6s %6s %6s %6s %7s", "operator", "total", "killed", "surv", "equiv", "score"))
    for _, op in ipairs(sorted_keys(report.per_operator)) do
        local s = report.per_operator[op]
        local d = s.total - s.equivalent
        print(string.format("%-18s %6d %6d %6d %6d %6.1f%%", op, s.total, s.killed, s.survived, s.equivalent,
            d > 0 and (s.killed / d * 100) or 0))
    end
    print(string.format("TOTAL SQL: %d/%d killed (%.1f%%), %d survived, %d equivalent, %d stillborn, %d duplicates",
        report.killed, denom, report.score, report.survived, report.equivalent,
        report.stillborn, report.duplicates))
    print(string.format("  kill signals: diagnostics=%d, crash=%d",
        report.kill_reasons.diagnostics or 0, report.kill_reasons.crash or 0))
    if report.equivalent > 0 then
        local parts = {}
        for _, cat in ipairs(sorted_keys(report.equivalent_by_category)) do
            table.insert(parts, string.format("%s=%d", cat, report.equivalent_by_category[cat]))
        end
        print("  equivalents by category: " .. table.concat(parts, ", "))
        local by_view = {}
        for _, e in ipairs(report.equivalents) do
            by_view[e.view] = by_view[e.view] or {}
            table.insert(by_view[e.view], string.format("%s: %s [%s]", e.operator, e.desc:sub(1, 50), e.category or "?"))
        end
        for _, v in ipairs(sorted_keys(by_view)) do
            print("    " .. v)
            for _, line in ipairs(by_view[v]) do print("      = " .. line) end
        end
    end
    if #report.dead_views > 0 then
        print("  unreachable queries (all mutants equivalent): " .. table.concat(report.dead_views, ", "))
    end
    if report.survived > 0 then
        print(string.format("  %d unclassified survivor(s): add a fixture that distinguishes them, or an entry to %s",
            report.survived, config.equivalents_file))
    end

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
                    -- Skip expect_errors suites (they test analyze_queries, not source logic)
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
        local denom = sql_report.total - (sql_report.equivalent or 0)
        local s = denom > 0 and (sql_report.killed / denom * 100) or 0
        print(string.format("  SQL:  %d/%d killed (%.1f%%), %d survived, %d equivalent, %d stillborn, %d duplicates",
            sql_report.killed, denom, s, sql_report.survived, sql_report.equivalent or 0,
            sql_report.stillborn or 0, sql_report.duplicates or 0))
    end
    if lua_report then
        local s = lua_report.total > 0 and (lua_report.killed / lua_report.total * 100) or 0
        print(string.format("  Lua:  %d/%d killed (%.1f%%)", lua_report.killed, lua_report.total, s))
    end
end

return {{Meta = Meta}}
