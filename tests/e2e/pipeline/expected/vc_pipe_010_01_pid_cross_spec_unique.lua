-- Test oracle for VC-PIPE-010: Cross-Specification PID Auto-Generation
--
-- PIDs must be unique across all specifications (HLR-PIPE-009, LLR-042):
-- the relation resolver falls back to a project-wide PID lookup and
-- view_object_duplicate_pid groups by PID alone. Two documents whose HLRs lack
-- explicit @PID must therefore not both receive HLR-001, an auto-generated PID
-- must skip an explicit PID claimed in ANOTHER document, and an incremental
-- rebuild of one document must not collide with the cached other documents.
--
-- Uses in-process engine execution like vc_pipe_013_01_stale_relation_rebind.

return function(_, _)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local sqlite = require("lsqlite3")

    local function fail(msg)
        return false, msg
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
        collectgarbage("collect")
        return { ok = false, err = tostring(result) }
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

    local function rows(db, sql)
        local stmt = db:prepare(sql)
        if not stmt then
            error(db:errmsg())
        end
        local out = {}
        for r in stmt:nrows() do
            table.insert(out, r)
        end
        stmt:finalize()
        return out
    end

    -- Snapshot of every HLR (spec, title, pid) plus any duplicated PIDs.
    local function snapshot(db)
        local snap = { by_title = {}, hlr_count = 0 }
        for _, r in ipairs(rows(db, [[
            SELECT specification_ref, title_text, pid FROM spec_objects
            WHERE type_ref = 'HLR'
        ]])) do
            snap.hlr_count = snap.hlr_count + 1
            snap.by_title[r.title_text] = r.pid
        end
        snap.dupes = rows(db, [[
            SELECT pid, COUNT(*) AS n, GROUP_CONCAT(specification_ref) AS specs
            FROM spec_objects WHERE pid IS NOT NULL
            GROUP BY pid HAVING COUNT(*) > 1
        ]])
        snap.spec_dupes = rows(db, [[
            SELECT pid, COUNT(*) AS n FROM specifications WHERE pid IS NOT NULL
            GROUP BY pid HAVING COUNT(*) > 1
        ]])
        return snap
    end

    local function check(label, run, snap, expected_hlrs)
        if #snap.dupes > 0 then
            local parts = {}
            for _, d in ipairs(snap.dupes) do
                table.insert(parts, string.format("%s x%d (specs: %s)", d.pid, d.n, d.specs))
            end
            return false, label .. ": duplicate object PIDs across specifications: "
                .. table.concat(parts, "; ")
        end
        if #snap.spec_dupes > 0 then
            return false, label .. ": duplicate specification PID " .. tostring(snap.spec_dupes[1].pid)
        end
        if snap.hlr_count ~= expected_hlrs then
            return false, string.format("%s: expected %d HLRs, got %d",
                label, expected_hlrs, snap.hlr_count)
        end
        for title, pid in pairs(snap.by_title) do
            if not pid or pid == "" then
                return false, label .. ": HLR '" .. title .. "' has no PID"
            end
        end
        if snap.by_title["B explicit"] ~= "HLR-002" then
            return false, label .. ": explicit @HLR-002 was not preserved (got "
                .. tostring(snap.by_title["B explicit"]) .. ")"
        end
        -- Any error aborts the build (and its cache bookkeeping), which would
        -- turn the incremental run into a full rebuild.
        local errors = (run.diagnostics and run.diagnostics.errors) or {}
        if #errors > 0 then
            return false, string.format("%s: build raised %d error(s), first: [%s] %s",
                label, #errors, tostring(errors[1].code), tostring(errors[1].message))
        end
        return true
    end

    local probe_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base_dir = "tests/e2e/pipeline/build/pid_cross_spec_probe_" .. probe_id
    local doc_a = base_dir .. "/doc_a.md"
    local doc_b = base_dir .. "/doc_b.md"
    local doc_c = base_dir .. "/doc_c.md"
    local output_dir = base_dir .. "/build"
    local db_path = output_dir .. "/specir.db"

    local project_info = {
        project = { code = "PIDXSPEC", name = "Cross-Spec PID Probe" },
        template = "sw_docs",
        files = { doc_a, doc_b, doc_c },
        output_dir = output_dir,
        output_format = "markdown",
        outputs = {
            { format = "markdown", path = output_dir .. "/{spec_id}.md" },
        },
        db_file = db_path,
        logging = { level = "WARN", format = "console", color = false },
        -- Bare HLRs: silence the sw_docs traceability policies so the only
        -- errors left are the ones under test.
        validation = {
            traceability_hlr_to_vc = "ignore",
            traceability_hlr_allocation = "ignore",
        },
        project_root = ".",
    }

    task_runner.ensure_dir(base_dir)

    -- No spec declares a PID. doc_b explicitly claims HLR-002, which doc_a's
    -- sequential numbering would otherwise produce; doc_c's lone HLR would
    -- restart numbering at HLR-001 if collisions were only probed per spec.
    local ok, err = write_file(doc_a, [[
# SRS: Alpha

## HLR: A one

Body of A one.

## HLR: A two

Body of A two.
]])
    if not ok then
        return fail("Failed to write doc_a: " .. tostring(err))
    end

    ok, err = write_file(doc_b, [[
# SRS: Beta

## HLR: B one

Body of B one.

## HLR: B explicit @HLR-002

Body of B explicit.
]])
    if not ok then
        return fail("Failed to write doc_b: " .. tostring(err))
    end

    ok, err = write_file(doc_c, [[
# SRS: Gamma

## HLR: C one

Body of C one.
]])
    if not ok then
        return fail("Failed to write doc_c: " .. tostring(err))
    end

    -- Run 1: clean build of all documents
    local run1 = run_project(project_info)
    if not run1.ok then
        return fail("Run 1 failed: " .. tostring(run1.err))
    end

    local snap1, err1 = with_db(db_path, snapshot)
    if not snap1 then
        return fail("Run 1 DB query failed: " .. tostring(err1))
    end
    local pass, msg = check("Run 1", run1, snap1, 5)
    if not pass then
        return fail(msg)
    end

    require("luv").sleep(1000)

    -- Run 2: edit doc_b only (doc_a and doc_c stay cached) and add an HLR
    -- without PID.
    ok, err = write_file(doc_b, [[
# SRS: Beta

## HLR: B one

Body of B one.

## HLR: B explicit @HLR-002

Body of B explicit.

## HLR: B three

Newly added requirement without explicit PID.
]])
    if not ok then
        return fail("Failed to update doc_b: " .. tostring(err))
    end

    local run2 = run_project(project_info)
    if not run2.ok then
        return fail("Run 2 failed: " .. tostring(run2.err))
    end

    local snap2, err2 = with_db(db_path, snapshot)
    if not snap2 then
        return fail("Run 2 DB query failed: " .. tostring(err2))
    end
    pass, msg = check("Run 2", run2, snap2, 6)
    if not pass then
        return fail(msg)
    end

    -- The cached documents' PIDs must not shift because doc_b was rebuilt.
    for _, title in ipairs({ "A one", "A two", "C one" }) do
        if snap2.by_title[title] ~= snap1.by_title[title] then
            return fail(string.format("Run 2: cached PID for '%s' changed %s -> %s",
                title, tostring(snap1.by_title[title]), tostring(snap2.by_title[title])))
        end
    end

    return true
end
