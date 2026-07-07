-- Test oracle for VC-PIPE-014: Incremental Cross-Document View Freshness
--
-- doc_b contains a traceability matrix whose rows include data from doc_a
-- (the HLR title). Editing doc_a leaves doc_b cache-clean, but doc_b's
-- emitted output must still be regenerated: the matrix renders live from the
-- DB, so the assembled document changed. A no-op rerun afterwards must still
-- be a cache hit (the emit-input hash must be deterministic).
--
-- Uses in-process engine execution like vc_009_01_incremental_cache.

return function(_, _)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local sqlite = require("lsqlite3")

    local function fail(msg)
        return false, msg
    end

    local function contains(haystack, needle)
        return type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
    end

    local function read_file(path)
        local f = io.open(path, "r")
        if not f then return nil end
        local c = f:read("*a")
        f:close()
        return c
    end

    local function write_file(path, content)
        local dir = path:match("^(.+)/[^/]+$")
        if dir then task_runner.ensure_dir(dir) end
        local ok, err = task_runner.write_file(path, content)
        if not ok then return nil, err or "write failed" end
        return true
    end

    local function run_project(project_info)
        local ok, result = pcall(engine.run_project, project_info)
        if ok then return { ok = true, diagnostics = result } end
        collectgarbage("collect")
        return { ok = false, err = tostring(result) }
    end

    local function output_cache_time(db_path, spec_id, output_path)
        local db = sqlite.open(db_path)
        if not db then return nil end
        local stmt = db:prepare([[
            SELECT generated_at AS ts FROM output_cache
            WHERE spec_id = :spec AND output_path = :path
        ]])
        if not stmt then db:close() return nil end
        stmt:bind_names({ spec = spec_id, path = output_path })
        local ts = nil
        if stmt:step() == sqlite.ROW then
            local row = stmt:get_named_values()
            ts = row and row.ts or nil
        end
        stmt:finalize()
        db:close()
        return ts
    end

    local probe_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base_dir = "tests/e2e/pipeline/build/stale_view_probe_" .. probe_id
    local doc_a = base_dir .. "/doc_a.md"
    local doc_b = base_dir .. "/doc_b.md"
    local output_dir = base_dir .. "/build"
    local db_path = output_dir .. "/specir.db"
    local out_b = output_dir .. "/doc_b.md"

    local project_info = {
        project = { code = "STALEVIEW", name = "Stale Cross-Doc View Probe" },
        template = "sw_docs",
        files = { doc_a, doc_b },
        output_dir = output_dir,
        output_format = "markdown",
        outputs = {
            { format = "markdown", path = output_dir .. "/{spec_id}.md" },
        },
        db_file = db_path,
        logging = { level = "WARN", format = "console", color = false },
        -- Minimal fixture has no SF/FD/CSC allocation chain; not what this
        -- test verifies, so downgrade that analyzer to a warning.
        validation = { traceability_hlr_allocation = "warn" },
        project_root = ".",
    }

    task_runner.ensure_dir(base_dir)

    -- doc_a holds only the TR whose result feeds doc_b's matrix through an
    -- INBOUND relation (owned by doc_a). doc_b's own rows never change in
    -- this test, so a per-spec dependency hash of doc_b cannot see the edit.
    local ok, err = write_file(doc_a, [[
# SRS: Spec A @SRS-A-001

## TR: Authentication Run @TR-A-001

> result: Pass

> traceability: [VC-B-001](@)
]])
    if not ok then return fail("Failed to write doc_a: " .. tostring(err)) end

    ok, err = write_file(doc_b, [[
# SRS: Spec B @SRS-B-001

## HLR: Authentication Requirement @HLR-B-001

> status: Approved

Authentication must validate credentials.

## VC: Verify Authentication @VC-B-001

> objective: Verify the requirement.

> verification_method: Test

> traceability: [HLR-B-001](@)

`traceability_matrix:`
]])
    if not ok then return fail("Failed to write doc_b: " .. tostring(err)) end

    -- Run 1: initial build; doc_b's matrix must show doc_a's TR result
    local run1 = run_project(project_info)
    if not run1.ok then return fail("Run 1 failed: " .. tostring(run1.err)) end

    local out1 = read_file(out_b)
    if not out1 then return fail("Missing doc_b output after run 1") end
    if not contains(out1, "Pass") then
        return fail("Run 1 matrix in doc_b missing TR result from doc_a")
    end

    os.execute("sleep 1")

    -- Run 2: flip the TR result in doc_a; doc_b is cache-clean but its
    -- matrix content changed, so its output must be regenerated.
    ok, err = write_file(doc_a, [[
# SRS: Spec A @SRS-A-001

## TR: Authentication Run @TR-A-001

> result: Fail

> traceability: [VC-B-001](@)
]])
    if not ok then return fail("Failed to update doc_a: " .. tostring(err)) end

    local run2 = run_project(project_info)
    if not run2.ok then return fail("Run 2 failed: " .. tostring(run2.err)) end

    local out2 = read_file(out_b)
    if not out2 then return fail("Missing doc_b output after run 2") end
    if contains(out2, "Pass") then
        return fail("Run 2: doc_b matrix still shows stale TR result from before doc_a's edit")
    end
    if not contains(out2, "Fail") then
        return fail("Run 2: doc_b matrix missing updated TR result")
    end

    local t2 = output_cache_time(db_path, "doc_b", out_b)
    if not t2 then return fail("Run 2 missing output_cache row for doc_b") end

    os.execute("sleep 1")

    -- Run 3: no changes; both outputs must be cache hits (deterministic hash)
    local run3 = run_project(project_info)
    if not run3.ok then return fail("Run 3 failed: " .. tostring(run3.err)) end

    local t3 = output_cache_time(db_path, "doc_b", out_b)
    if t3 ~= t2 then
        return fail("Run 3 regenerated doc_b output on a no-change rerun (nondeterministic emit-input hash?)")
    end

    return true
end
