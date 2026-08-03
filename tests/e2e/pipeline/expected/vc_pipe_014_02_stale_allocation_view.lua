-- Test oracle for VC-PIPE-014 (TP 02): Incremental Allocation View Freshness
--
-- doc_b contains `allocation_matrix:` whose rows include doc_a's HLR title.
-- Editing doc_a leaves doc_b cache-clean, but doc_b's emitted matrix must
-- still reflect the edit: the view must render live from the DB, never from
-- a stale precomputed AST. A no-op rerun afterwards must still be a cache
-- hit (the emit-input hash must be deterministic).
--
-- Uses in-process engine execution like vc_pipe_014_01_stale_view_cross_doc.

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
    local base_dir = "tests/e2e/pipeline/build/stale_alloc_probe_" .. probe_id
    local doc_a = base_dir .. "/doc_a.md"
    local doc_b = base_dir .. "/doc_b.md"
    local output_dir = base_dir .. "/build"
    local db_path = output_dir .. "/specir.db"
    local out_b = output_dir .. "/doc_b.md"

    local project_info = {
        project = { code = "STALEALLOC", name = "Stale Allocation View Probe" },
        template = "sw_docs",
        files = { doc_a, doc_b },
        output_dir = output_dir,
        output_format = "markdown",
        outputs = {
            { format = "markdown", path = output_dir .. "/{spec_id}.md" },
        },
        db_file = db_path,
        logging = { level = "WARN", format = "console", color = false },
        -- Minimal fixture has no SF/FD/CSC allocation chain; incomplete chains
        -- are exactly what the matrix should report, so downgrade the analyzer.
        validation = {
            traceability_hlr_allocation = "warn",
            traceability_hlr_to_vc = "ignore",
        },
        project_root = ".",
    }

    task_runner.ensure_dir(base_dir)

    -- doc_a holds the HLR whose title feeds doc_b's allocation matrix.
    -- doc_b's own rows never change in this test.
    local ok, err = write_file(doc_a, [[
# SRS: Spec A @SRS-AL-001

## HLR: Alpha Requirement @HLR-AL-001

> status: Approved

Authentication must validate credentials.
]])
    if not ok then return fail("Failed to write doc_a: " .. tostring(err)) end

    ok, err = write_file(doc_b, [[
# SDD: Spec B @SDD-AL-001

## Allocation

`allocation_matrix:`
]])
    if not ok then return fail("Failed to write doc_b: " .. tostring(err)) end

    -- Run 1: initial build; doc_b's matrix must show doc_a's HLR title
    local run1 = run_project(project_info)
    if not run1.ok then return fail("Run 1 failed: " .. tostring(run1.err)) end

    local out1 = read_file(out_b)
    if not out1 then return fail("Missing doc_b output after run 1") end
    if not contains(out1, "HLR-AL-001") or not contains(out1, "Alpha Requirement") then
        return fail("Run 1 matrix in doc_b missing HLR row from doc_a")
    end

    os.execute("sleep 1")

    -- Run 2: retitle the HLR in doc_a; doc_b is cache-clean but its matrix
    -- content changed, so its output must show the new title.
    ok, err = write_file(doc_a, [[
# SRS: Spec A @SRS-AL-001

## HLR: Renamed Requirement @HLR-AL-001

> status: Approved

Authentication must validate credentials.
]])
    if not ok then return fail("Failed to update doc_a: " .. tostring(err)) end

    local run2 = run_project(project_info)
    if not run2.ok then return fail("Run 2 failed: " .. tostring(run2.err)) end

    local out2 = read_file(out_b)
    if not out2 then return fail("Missing doc_b output after run 2") end
    if contains(out2, "Alpha Requirement") then
        return fail("Run 2: doc_b allocation matrix still shows the stale HLR title "
            .. "from before doc_a's edit (stale precomputed view)")
    end
    if not contains(out2, "Renamed Requirement") then
        return fail("Run 2: doc_b allocation matrix missing the updated HLR title")
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
