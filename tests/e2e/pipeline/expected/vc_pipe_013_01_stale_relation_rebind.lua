-- Test oracle for VC-PIPE-013: Incremental Stale Relation Rebind
--
-- Rebuilding a document deletes and re-inserts its spec_objects rows, and
-- SQLite reuses the freed rowids. A cached document's resolved
-- target_object_id can therefore silently rebind to a DIFFERENT object of the
-- rebuilt spec (the id still exists, so dangling-target cleanup misses it).
-- Relations pointing into a rebuilt spec must be re-resolved by target_text,
-- or become unresolved when the target no longer exists.
--
-- Uses in-process engine execution like vc_009_01_incremental_cache.

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

    -- Fetch the doc_a relation joined to the pid of its resolved target object.
    local function get_relation(db)
        local stmt = db:prepare([[
            SELECT r.target_text, r.target_object_id, o.pid AS target_pid
            FROM spec_relations r
            LEFT JOIN spec_objects o ON o.id = r.target_object_id
            WHERE r.specification_ref = 'doc_a'
        ]])
        if not stmt then
            error(db:errmsg())
        end
        local row = nil
        local count = 0
        for r in stmt:nrows() do
            count = count + 1
            row = r
        end
        stmt:finalize()
        return { row = row, count = count }
    end

    local probe_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base_dir = "tests/e2e/pipeline/build/stale_relation_probe_" .. probe_id
    local doc_a = base_dir .. "/doc_a.md"
    local doc_b = base_dir .. "/doc_b.md"
    local output_dir = base_dir .. "/build"
    local db_path = output_dir .. "/specir.db"

    local project_info = {
        project = { code = "STALEREL", name = "Stale Relation Rebind Probe" },
        template = "default",
        files = { doc_a, doc_b },
        output_dir = output_dir,
        output_format = "markdown",
        outputs = {
            { format = "markdown", path = output_dir .. "/{spec_id}.md" },
        },
        db_file = db_path,
        logging = { level = "WARN", format = "console", color = false },
        validation = nil,
        project_root = ".",
    }

    task_runner.ensure_dir(base_dir)

    local ok, err = write_file(doc_a, [[
# Spec A @SRS-A

## Req A1 @REQ-A-001

Requirement A1 traces to a requirement in Spec B.

> traceability: [REQ-B-002](@)
]])
    if not ok then
        return fail("Failed to write doc_a: " .. tostring(err))
    end

    ok, err = write_file(doc_b, [[
# Spec B @SRS-B

## Req B1 @REQ-B-001

Body of B1.

## Req B2 @REQ-B-002

Body of B2.
]])
    if not ok then
        return fail("Failed to write doc_b: " .. tostring(err))
    end

    -- Run 1: initial build; relation must resolve to REQ-B-002
    local run1 = run_project(project_info)
    if not run1.ok then
        return fail("Run 1 failed: " .. tostring(run1.err))
    end

    local rel1, err1 = with_db(db_path, get_relation)
    if not rel1 then
        return fail("Run 1 DB query failed: " .. tostring(err1))
    end
    if rel1.count ~= 1 then
        return fail("Run 1 expected exactly 1 doc_a relation, got " .. tostring(rel1.count))
    end
    if not rel1.row.target_object_id or rel1.row.target_pid ~= "REQ-B-002" then
        return fail("Run 1 relation did not resolve to REQ-B-002 (pid="
            .. tostring(rel1.row.target_pid) .. ")")
    end

    os.execute("sleep 1")

    -- Run 2: edit doc_b so REQ-B-002 still exists but its rowid shifts
    -- (new object inserted before it). doc_a stays cached.
    ok, err = write_file(doc_b, [[
# Spec B @SRS-B

## Req B0 @REQ-B-000

Newly inserted requirement shifts the rowids of B1 and B2.

## Req B1 @REQ-B-001

Body of B1.

## Req B2 @REQ-B-002

Body of B2.
]])
    if not ok then
        return fail("Failed to update doc_b (shift scenario): " .. tostring(err))
    end

    local run2 = run_project(project_info)
    if not run2.ok then
        return fail("Run 2 failed: " .. tostring(run2.err))
    end

    local rel2, err2 = with_db(db_path, get_relation)
    if not rel2 then
        return fail("Run 2 DB query failed: " .. tostring(err2))
    end
    if rel2.count ~= 1 then
        return fail("Run 2 expected exactly 1 doc_a relation, got " .. tostring(rel2.count))
    end
    if rel2.row.target_pid ~= "REQ-B-002" then
        return fail("Run 2 relation rebound to wrong object after target spec rebuild: "
            .. "target_text=" .. tostring(rel2.row.target_text)
            .. " resolved pid=" .. tostring(rel2.row.target_pid))
    end

    os.execute("sleep 1")

    -- Run 3: edit doc_b to REMOVE REQ-B-002 entirely. The doc_a relation must
    -- become unresolved — not stay bound to whatever object reuses the rowid.
    ok, err = write_file(doc_b, [[
# Spec B @SRS-B

## Req B0 @REQ-B-000

Still here.

## Req B1 @REQ-B-001

Body of B1.
]])
    if not ok then
        return fail("Failed to update doc_b (removal scenario): " .. tostring(err))
    end

    local run3 = run_project(project_info)
    if not run3.ok then
        return fail("Run 3 failed: " .. tostring(run3.err))
    end

    local rel3, err3 = with_db(db_path, get_relation)
    if not rel3 then
        return fail("Run 3 DB query failed: " .. tostring(err3))
    end
    if rel3.count ~= 1 then
        return fail("Run 3 expected exactly 1 doc_a relation, got " .. tostring(rel3.count))
    end
    if rel3.row.target_object_id ~= nil then
        return fail("Run 3 relation to deleted REQ-B-002 survived incremental rebuild: "
            .. "still bound to object id=" .. tostring(rel3.row.target_object_id)
            .. " (pid=" .. tostring(rel3.row.target_pid) .. ")")
    end
    if rel3.row.target_text ~= "REQ-B-002" then
        return fail("Run 3 relation lost its target_text: " .. tostring(rel3.row.target_text))
    end

    return true
end
