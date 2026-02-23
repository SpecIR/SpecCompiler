-- Test oracle for VC-007: Incremental Build and Cache Semantics
-- Uses in-process engine execution so incremental paths count toward coverage.

return function(_, _)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local sqlite = require("lsqlite3")

    local function contains(haystack, needle)
        return type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
    end

    local function fail(msg)
        return false, msg
    end

    local function read_file(path)
        local f = io.open(path, "r")
        if not f then
            return nil
        end
        local c = f:read("*a")
        f:close()
        return c
    end

    local function write_file(path, content)
        local dir = path:match("^(.+)/[^/]+$")
        if dir then
            task_runner.ensure_dir(dir)
        end
        local ok, err = task_runner.write_file(path, content)
        if not ok then
            return nil, err or "write failed"
        end
        return true
    end

    local function run_project(project_info)
        local ok, result = pcall(engine.run_project, project_info)
        if ok then
            return { ok = true, diagnostics = result }
        end
        -- Ensure leaked handles from failed runs are collectible before next run.
        collectgarbage("collect")
        return { ok = false, err = tostring(result) }
    end

    local function query_scalar(db, sql, params, column)
        local stmt, err = db:prepare(sql)
        if not stmt then
            return nil, err or db:errmsg()
        end
        if params then
            stmt:bind_names(params)
        end

        local value = nil
        local rc = stmt:step()
        if rc == sqlite.ROW then
            local row = stmt:get_named_values()
            value = row and row[column] or nil
        end
        stmt:finalize()
        return value, nil
    end

    local function with_db(db_path, fn)
        local db = sqlite.open(db_path)
        if not db then
            return nil, "Failed to open DB: " .. db_path
        end
        local ok, v1, v2 = pcall(fn, db)
        db:close()
        if not ok then
            return nil, tostring(v1)
        end
        return v1, v2
    end

    local function output_cache_time(db, spec_id, output_path)
        return query_scalar(db, [[
            SELECT generated_at AS ts
            FROM output_cache
            WHERE spec_id = :spec AND output_path = :path
        ]], { spec = spec_id, path = output_path }, "ts")
    end

    local function build_graph_hash(db, root_path, node_path)
        return query_scalar(db, [[
            SELECT node_sha1 AS h
            FROM build_graph
            WHERE root_path = :root AND node_path = :node
        ]], { root = root_path, node = node_path }, "h")
    end

    local function sleep_tick()
        os.execute("sleep 1")
    end

    local probe_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base_dir = "tests/e2e/pipeline/build/incremental_cache_probe_" .. probe_id
    local include_path = base_dir .. "/includes/part.md"
    local doc_path = base_dir .. "/doc.md"
    local output_dir = base_dir .. "/build"
    local db_path = output_dir .. "/specir.db"
    local json_out_path = output_dir .. "/doc.json"
    local md_out_path = output_dir .. "/doc.md"

    local project_info = {
        project = { code = "INCR", name = "Incremental Cache Probe" },
        template = "default",
        files = { doc_path },
        output_dir = output_dir,
        output_format = "json",
        outputs = {
            { format = "json", path = output_dir .. "/{spec_id}.json" },
            { format = "markdown", path = output_dir .. "/{spec_id}.md" },
        },
        db_file = db_path,
        logging = { level = "INFO", format = "console", color = false },
        validation = nil,
        project_root = ".",
    }

    task_runner.ensure_dir(base_dir .. "/includes")

    local ok, err = write_file(doc_path, [[
# SPEC: Incremental Cache Probe @SPEC-INC-001

## SECTION: Intro @SEC-001

```include
includes/part.md
```
]])
    if not ok then
        return fail("Failed to write root document: " .. tostring(err))
    end

    ok, err = write_file(include_path, [[
## SECTION: Included @SEC-INC-001

Included v1 text.
]])
    if not ok then
        return fail("Failed to write include document: " .. tostring(err))
    end

    -- Run 1: initial build
    local run1 = run_project(project_info)
    if not run1.ok then
        return fail("Run 1 failed: " .. tostring(run1.err))
    end

    local out1 = read_file(md_out_path)
    if not out1 then
        return fail("Missing generated markdown output after run 1: " .. md_out_path)
    end
    if not contains(out1, "Included v1 text.") and not contains(out1, "[v1]{") then
        return fail("Run 1 output missing include v1 content")
    end

    local t1_json, t1_md = with_db(db_path, function(db)
        return output_cache_time(db, "doc", json_out_path), output_cache_time(db, "doc", md_out_path)
    end)
    if not t1_json or not t1_md then
        return fail("Run 1 missing output_cache entries for doc outputs")
    end

    local bg1 = with_db(db_path, function(db)
        return build_graph_hash(db, doc_path, include_path)
    end)
    if not bg1 or bg1 == "" then
        return fail("Run 1 missing build_graph hash for include dependency")
    end

    sleep_tick()

    -- Run 2: no changes, cache hit paths
    local run2 = run_project(project_info)
    if not run2.ok then
        return fail("Run 2 failed: " .. tostring(run2.err))
    end

    local t2_json, t2_md = with_db(db_path, function(db)
        return output_cache_time(db, "doc", json_out_path), output_cache_time(db, "doc", md_out_path)
    end)
    if not t2_json or not t2_md then
        return fail("Run 2 missing output_cache rows")
    end
    if t2_json ~= t1_json or t2_md ~= t1_md then
        return fail("Run 2 unexpectedly regenerated outputs (cache timestamps changed)")
    end

    local out2 = read_file(md_out_path)
    if out2 ~= out1 then
        return fail("Output changed on cache-hit run; expected identical markdown")
    end

    sleep_tick()

    -- Run 3: include changed, rebuild must occur
    ok, err = write_file(include_path, [[
## SECTION: Included @SEC-INC-001

Included v2 text.
]])
    if not ok then
        return fail("Failed to update include document: " .. tostring(err))
    end

    local run3 = run_project(project_info)
    if not run3.ok then
        return fail("Run 3 failed: " .. tostring(run3.err))
    end

    local t3_json, t3_md = with_db(db_path, function(db)
        return output_cache_time(db, "doc", json_out_path), output_cache_time(db, "doc", md_out_path)
    end)
    if not t3_json or not t3_md then
        return fail("Run 3 missing output_cache rows")
    end
    if t3_json == t2_json or t3_md == t2_md then
        return fail("Run 3 did not refresh output_cache timestamps after include change")
    end

    local bg3 = with_db(db_path, function(db)
        return build_graph_hash(db, doc_path, include_path)
    end)
    if bg3 == bg1 then
        return fail("Run 3 did not update include hash in build_graph after include change")
    end

    local out3 = read_file(md_out_path)
    if not out3 then
        return fail("Missing generated markdown output after run 3")
    end
    if not contains(out3, "Included v2 text.") and not contains(out3, "[v2]{") then
        return fail("Run 3 output missing updated include content")
    end
    if contains(out3, "Included v1 text.") or contains(out3, "[v1]{") then
        return fail("Run 3 output still contains stale include content")
    end

    sleep_tick()

    -- Run 4: remove one output artifact, expect selective regeneration
    local removed_json, rm_err = os.remove(json_out_path)
    if not removed_json then
        return fail("Failed to delete JSON output: " .. tostring(rm_err))
    end

    local run4 = run_project(project_info)
    if not run4.ok then
        return fail("Run 4 failed during output recovery: " .. tostring(run4.err))
    end

    local t4_json, t4_md = with_db(db_path, function(db)
        return output_cache_time(db, "doc", json_out_path), output_cache_time(db, "doc", md_out_path)
    end)
    if not t4_json or not t4_md then
        return fail("Run 4 missing output_cache rows after recovery")
    end
    if t4_json == t3_json then
        return fail("Run 4 did not regenerate missing JSON output")
    end
    if t4_md ~= t3_md then
        return fail("Run 4 unexpectedly regenerated unchanged markdown output")
    end

    local json_after = read_file(json_out_path)
    if not json_after or #json_after == 0 then
        return fail("Run 4 did not recreate non-empty JSON output")
    end

    -- Additional multi-document scenario: one dirty + one cached
    local multi_dir = base_dir .. "/multi_partial"
    local m_doc_a = multi_dir .. "/doc_a.md"
    local m_doc_b = multi_dir .. "/doc_b.md"
    local m_inc_a = multi_dir .. "/includes/a.md"
    local m_inc_b = multi_dir .. "/includes/b.md"
    local m_out_dir = multi_dir .. "/build"
    local m_db = m_out_dir .. "/specir.db"
    local m_out_a = m_out_dir .. "/doc_a.md"
    local m_out_b = m_out_dir .. "/doc_b.md"

    local multi_project = {
        project = { code = "INCRM", name = "Incremental Multi Probe" },
        template = "default",
        files = { m_doc_a, m_doc_b },
        output_dir = m_out_dir,
        output_format = "markdown",
        outputs = {
            { format = "markdown", path = m_out_dir .. "/{spec_id}.md" },
        },
        db_file = m_db,
        logging = { level = "INFO", format = "console", color = false },
        validation = nil,
        project_root = ".",
    }

    task_runner.ensure_dir(multi_dir .. "/includes")

    ok, err = write_file(m_doc_a, [[
# SPEC: Incremental A @SPEC-A-001

## SECTION: Intro A @SEC-A-001

```include
includes/a.md
```
]])
    if not ok then
        return fail("Failed to write multi doc_a: " .. tostring(err))
    end

    ok, err = write_file(m_doc_b, [[
# SPEC: Incremental B @SPEC-B-001

## SECTION: Intro B @SEC-B-001

```include
includes/b.md
```
]])
    if not ok then
        return fail("Failed to write multi doc_b: " .. tostring(err))
    end

    ok, err = write_file(m_inc_a, [[
## SECTION: Included A @SEC-INC-A-001

A v1.
]])
    if not ok then
        return fail("Failed to write include a: " .. tostring(err))
    end

    ok, err = write_file(m_inc_b, [[
## SECTION: Included B @SEC-INC-B-001

B v1.
]])
    if not ok then
        return fail("Failed to write include b: " .. tostring(err))
    end

    local m1 = run_project(multi_project)
    if not m1.ok then
        return fail("Multi run 1 failed: " .. tostring(m1.err))
    end

    sleep_tick()

    ok, err = write_file(m_inc_a, [[
## SECTION: Included A @SEC-INC-A-001

A v2.
]])
    if not ok then
        return fail("Failed to update include a: " .. tostring(err))
    end

    local m2 = run_project(multi_project)
    if not m2.ok then
        return fail("Multi run 2 failed: " .. tostring(m2.err))
    end

    local m_out_a_text = read_file(m_out_a)
    local m_out_b_text = read_file(m_out_b)
    if not m_out_a_text or not m_out_b_text then
        return fail("Missing multi-document outputs")
    end
    if not contains(m_out_a_text, "A v2.") and not contains(m_out_a_text, "[v2]{") then
        return fail("doc_a output was not rebuilt with updated include content")
    end
    if not contains(m_out_b_text, "B v1.") and not contains(m_out_b_text, "[v1]{") then
        return fail("doc_b output did not preserve expected content")
    end

    -- Final scenario: missing include must invalidate cache and fail fast.
    local removed, rm_include_err = os.remove(include_path)
    if not removed then
        return fail("Failed to delete include file for deletion scenario: " .. tostring(rm_include_err))
    end

    local run5 = run_project(project_info)
    if run5.ok then
        return fail("Run 5 unexpectedly succeeded after include deletion")
    end
    if not contains(run5.err, "Include file not found") then
        return fail("Run 5 failure did not report missing include file")
    end

    return true
end
