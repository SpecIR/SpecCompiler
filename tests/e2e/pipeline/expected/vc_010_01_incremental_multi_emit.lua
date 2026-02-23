-- Test oracle for VC-008: Incremental Multi-Document EMIT Completeness
-- Adversarial tests for the all-cached EMIT bypass bug.
-- Validates that ALL documents receive EMIT phase processing regardless of cache state.

return function(_, _)
    local engine = require("core.engine")
    local task_runner = require("infra.process.task_runner")
    local sqlite = require("lsqlite3")

    -- ========================================================================
    -- Helpers
    -- ========================================================================

    local function contains(haystack, needle)
        return type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil
    end

    local function fail(msg)
        return false, msg
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
        if ok then
            return { ok = true, diagnostics = result }
        end
        collectgarbage("collect")
        return { ok = false, err = tostring(result) }
    end

    local function query_scalar(db, sql, params, column)
        local stmt, err = db:prepare(sql)
        if not stmt then return nil, err or db:errmsg() end
        if params then stmt:bind_names(params) end
        local value = nil
        if stmt:step() == sqlite.ROW then
            local row = stmt:get_named_values()
            value = row and row[column] or nil
        end
        stmt:finalize()
        return value
    end

    local function query_count(db, sql, params)
        return query_scalar(db, sql, params, "cnt") or 0
    end

    local function with_db(db_path, fn)
        local db = sqlite.open(db_path)
        if not db then return nil, "Failed to open DB: " .. db_path end
        local ok, v1, v2 = pcall(fn, db)
        db:close()
        if not ok then return nil, tostring(v1) end
        return v1, v2
    end

    local function output_cache_time(db, spec_id, output_path)
        return query_scalar(db, [[
            SELECT generated_at AS ts FROM output_cache
            WHERE spec_id = :spec AND output_path = :path
        ]], { spec = spec_id, path = output_path }, "ts")
    end

    local function sleep_tick()
        os.execute("sleep 1")
    end

    -- ========================================================================
    -- Project factory
    -- ========================================================================

    local probe_id = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    local base_dir = "tests/e2e/pipeline/build/multi_emit_probe_" .. probe_id

    local function make_project(subdir, doc_names)
        local dir = base_dir .. "/" .. subdir
        local out_dir = dir .. "/build"
        local files = {}
        for _, name in ipairs(doc_names) do
            files[#files + 1] = dir .. "/" .. name .. ".md"
        end
        return {
            project = { code = "ADV", name = "Adversarial Cache Test" },
            template = "default",
            files = files,
            output_dir = out_dir,
            output_format = "markdown",
            outputs = {
                { format = "markdown", path = out_dir .. "/{spec_id}.md" },
            },
            db_file = out_dir .. "/specir.db",
            logging = { level = "WARN", format = "console", color = false },
            validation = nil,
            project_root = ".",
        }, dir, out_dir
    end

    -- ========================================================================
    -- SCENARIO 1: All-cached, delete non-first doc output, verify regeneration
    -- This catches the core bug: non-first docs were invisible in EMIT.
    -- ========================================================================

    local s1_proj, s1_dir, s1_out = make_project("s1_delete_nonfirst", {"doc_a", "doc_b", "doc_c"})

    write_file(s1_dir .. "/doc_a.md", [[
# SPEC: Doc A @SPEC-S1A

## SECTION: Intro A @SEC-S1A-001

Content from doc A.
]])
    write_file(s1_dir .. "/doc_b.md", [[
# SPEC: Doc B @SPEC-S1B

## SECTION: Intro B @SEC-S1B-001

Content from doc B.
]])
    write_file(s1_dir .. "/doc_c.md", [[
# SPEC: Doc C @SPEC-S1C

## SECTION: Intro C @SEC-S1C-001

Content from doc C.
]])

    -- Run 1: initial build
    local s1r1 = run_project(s1_proj)
    if not s1r1.ok then return fail("S1 Run 1 failed: " .. tostring(s1r1.err)) end

    -- Verify all 3 outputs exist
    for _, name in ipairs({"doc_a", "doc_b", "doc_c"}) do
        if not read_file(s1_out .. "/" .. name .. ".md") then
            return fail("S1 Run 1: missing output for " .. name)
        end
    end

    sleep_tick()

    -- Run 2: all cached, verify no regen
    local s1r2 = run_project(s1_proj)
    if not s1r2.ok then return fail("S1 Run 2 failed: " .. tostring(s1r2.err)) end

    -- Capture timestamps after run 2 (should match run 1)
    local s1_t2_a, s1_t2_b, s1_t2_c
    s1_t2_a = with_db(s1_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_a", s1_out .. "/doc_a.md")
    end)
    s1_t2_b = with_db(s1_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_b", s1_out .. "/doc_b.md")
    end)
    s1_t2_c = with_db(s1_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_c", s1_out .. "/doc_c.md")
    end)

    if not s1_t2_a or not s1_t2_b or not s1_t2_c then
        return fail("S1 Run 2: missing output_cache entries for one or more specs")
    end

    -- Delete doc_b output (non-first document)
    os.remove(s1_out .. "/doc_b.md")

    sleep_tick()

    -- Run 3: all cached, but doc_b output missing -> must regenerate
    local s1r3 = run_project(s1_proj)
    if not s1r3.ok then return fail("S1 Run 3 failed: " .. tostring(s1r3.err)) end

    -- KEY ASSERTION: doc_b output was regenerated
    local s1_b_after = read_file(s1_out .. "/doc_b.md")
    if not s1_b_after then
        return fail("S1: doc_b output was NOT regenerated after deletion (core bug)")
    end
    if not contains(s1_b_after, "Content from doc B") then
        return fail("S1: regenerated doc_b has wrong content")
    end

    -- Verify doc_a and doc_c unchanged (timestamps should match run 2)
    local s1_t3_a = with_db(s1_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_a", s1_out .. "/doc_a.md")
    end)
    local s1_t3_c = with_db(s1_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_c", s1_out .. "/doc_c.md")
    end)
    if s1_t3_a ~= s1_t2_a then
        return fail("S1: doc_a was unexpectedly regenerated")
    end
    if s1_t3_c ~= s1_t2_c then
        return fail("S1: doc_c was unexpectedly regenerated")
    end

    -- ========================================================================
    -- SCENARIO 2: All-cached, all outputs present -> verify all get cache entries
    -- ========================================================================

    local s2_proj, s2_dir, s2_out = make_project("s2_all_cached", {"doc_x", "doc_y", "doc_z"})

    write_file(s2_dir .. "/doc_x.md", [[
# SPEC: Doc X @SPEC-S2X

## SECTION: Intro X @SEC-S2X-001

Content X.
]])
    write_file(s2_dir .. "/doc_y.md", [[
# SPEC: Doc Y @SPEC-S2Y

## SECTION: Intro Y @SEC-S2Y-001

Content Y.
]])
    write_file(s2_dir .. "/doc_z.md", [[
# SPEC: Doc Z @SPEC-S2Z

## SECTION: Intro Z @SEC-S2Z-001

Content Z.
]])

    -- Run 1: initial build
    local s2r1 = run_project(s2_proj)
    if not s2r1.ok then return fail("S2 Run 1 failed: " .. tostring(s2r1.err)) end

    -- Capture run 1 timestamps
    local s2_t1_x = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_x", s2_out .. "/doc_x.md")
    end)
    local s2_t1_y = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_y", s2_out .. "/doc_y.md")
    end)
    local s2_t1_z = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_z", s2_out .. "/doc_z.md")
    end)

    if not s2_t1_x or not s2_t1_y or not s2_t1_z then
        return fail("S2 Run 1: missing output_cache entries")
    end

    sleep_tick()

    -- Run 2: all cached
    local s2r2 = run_project(s2_proj)
    if not s2r2.ok then return fail("S2 Run 2 failed: " .. tostring(s2r2.err)) end

    -- Verify ALL output_cache timestamps unchanged (not just first doc)
    local s2_t2_x = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_x", s2_out .. "/doc_x.md")
    end)
    local s2_t2_y = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_y", s2_out .. "/doc_y.md")
    end)
    local s2_t2_z = with_db(s2_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_z", s2_out .. "/doc_z.md")
    end)

    if s2_t2_x ~= s2_t1_x then
        return fail("S2: doc_x unexpectedly regenerated on all-cached build")
    end
    if s2_t2_y ~= s2_t1_y then
        return fail("S2: doc_y unexpectedly regenerated on all-cached build")
    end
    if s2_t2_z ~= s2_t1_z then
        return fail("S2: doc_z unexpectedly regenerated on all-cached build")
    end

    -- ========================================================================
    -- SCENARIO 3: Partial dirty + cached output deletion
    -- Modify doc_a source + delete doc_c output (source unchanged)
    -- ========================================================================

    local s3_proj, s3_dir, s3_out = make_project("s3_partial_dirty", {"doc_a", "doc_b", "doc_c"})

    write_file(s3_dir .. "/doc_a.md", [[
# SPEC: S3 Doc A @SPEC-S3A

## SECTION: Intro @SEC-S3A-001

S3A v1.
]])
    write_file(s3_dir .. "/doc_b.md", [[
# SPEC: S3 Doc B @SPEC-S3B

## SECTION: Intro @SEC-S3B-001

S3B content.
]])
    write_file(s3_dir .. "/doc_c.md", [[
# SPEC: S3 Doc C @SPEC-S3C

## SECTION: Intro @SEC-S3C-001

S3C content.
]])

    -- Run 1: initial build
    local s3r1 = run_project(s3_proj)
    if not s3r1.ok then return fail("S3 Run 1 failed: " .. tostring(s3r1.err)) end

    local s3_t1_b = with_db(s3_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_b", s3_out .. "/doc_b.md")
    end)

    sleep_tick()

    -- Modify doc_a (makes it dirty)
    write_file(s3_dir .. "/doc_a.md", [[
# SPEC: S3 Doc A @SPEC-S3A

## SECTION: Intro @SEC-S3A-001

S3A v2 modified.
]])

    -- Delete doc_c output (source unchanged, so it's cached)
    os.remove(s3_out .. "/doc_c.md")

    -- Run 2: doc_a dirty, doc_b+c cached, doc_c output missing
    local s3r2 = run_project(s3_proj)
    if not s3r2.ok then return fail("S3 Run 2 failed: " .. tostring(s3r2.err)) end

    -- doc_a rebuilt with new content
    local s3_a_out = read_file(s3_out .. "/doc_a.md")
    if not s3_a_out then
        return fail("S3: doc_a output missing after dirty rebuild")
    end
    if not contains(s3_a_out, "S3A v2 modified") then
        return fail("S3: doc_a output doesn't contain updated content")
    end

    -- doc_b unchanged
    local s3_t2_b = with_db(s3_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_b", s3_out .. "/doc_b.md")
    end)
    if s3_t2_b ~= s3_t1_b then
        return fail("S3: doc_b was unexpectedly regenerated")
    end

    -- doc_c regenerated (output was deleted)
    local s3_c_out = read_file(s3_out .. "/doc_c.md")
    if not s3_c_out then
        return fail("S3: doc_c output was NOT regenerated after deletion")
    end
    if not contains(s3_c_out, "S3C content") then
        return fail("S3: regenerated doc_c has wrong content")
    end

    -- ========================================================================
    -- SCENARIO 4: Sequential progressive changes
    -- Build 1: all dirty. Build 2: all cached. Build 3: modify B.
    -- Build 4: all cached again.
    -- ========================================================================

    local s4_proj, s4_dir, s4_out = make_project("s4_sequential", {"doc_p", "doc_q", "doc_r"})

    write_file(s4_dir .. "/doc_p.md", [[
# SPEC: S4P @SPEC-S4P

## SECTION: Intro @SEC-S4P-001

P v1.
]])
    write_file(s4_dir .. "/doc_q.md", [[
# SPEC: S4Q @SPEC-S4Q

## SECTION: Intro @SEC-S4Q-001

Q v1.
]])
    write_file(s4_dir .. "/doc_r.md", [[
# SPEC: S4R @SPEC-S4R

## SECTION: Intro @SEC-S4R-001

R v1.
]])

    -- Build 1: all dirty
    local s4r1 = run_project(s4_proj)
    if not s4r1.ok then return fail("S4 Build 1 failed: " .. tostring(s4r1.err)) end

    local s4_t1_p = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_p", s4_out .. "/doc_p.md")
    end)
    local s4_t1_r = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_r", s4_out .. "/doc_r.md")
    end)

    sleep_tick()

    -- Build 2: all cached
    local s4r2 = run_project(s4_proj)
    if not s4r2.ok then return fail("S4 Build 2 failed: " .. tostring(s4r2.err)) end

    -- Verify no regen
    local s4_t2_p = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_p", s4_out .. "/doc_p.md")
    end)
    if s4_t2_p ~= s4_t1_p then
        return fail("S4 Build 2: doc_p unexpectedly regenerated")
    end

    sleep_tick()

    -- Build 3: modify doc_q
    write_file(s4_dir .. "/doc_q.md", [[
# SPEC: S4Q @SPEC-S4Q

## SECTION: Intro @SEC-S4Q-001

Q v2 updated.
]])

    local s4r3 = run_project(s4_proj)
    if not s4r3.ok then return fail("S4 Build 3 failed: " .. tostring(s4r3.err)) end

    -- doc_q rebuilt
    local s4_q_out = read_file(s4_out .. "/doc_q.md")
    if not contains(s4_q_out, "Q v2 updated") then
        return fail("S4 Build 3: doc_q not rebuilt with updated content")
    end

    -- doc_p and doc_r unchanged
    local s4_t3_p = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_p", s4_out .. "/doc_p.md")
    end)
    local s4_t3_r = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_r", s4_out .. "/doc_r.md")
    end)
    if s4_t3_p ~= s4_t1_p then
        return fail("S4 Build 3: doc_p unexpectedly regenerated")
    end
    if s4_t3_r ~= s4_t1_r then
        return fail("S4 Build 3: doc_r unexpectedly regenerated")
    end

    sleep_tick()

    -- Build 4: all cached again
    local s4r4 = run_project(s4_proj)
    if not s4r4.ok then return fail("S4 Build 4 failed: " .. tostring(s4r4.err)) end

    -- All timestamps should match build 3 (no regen)
    local s4_t4_p = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_p", s4_out .. "/doc_p.md")
    end)
    local s4_t4_q = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_q", s4_out .. "/doc_q.md")
    end)
    local s4_t4_r = with_db(s4_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_r", s4_out .. "/doc_r.md")
    end)
    if s4_t4_p ~= s4_t3_p then
        return fail("S4 Build 4: doc_p unexpectedly regenerated")
    end
    if s4_t4_r ~= s4_t3_r then
        return fail("S4 Build 4: doc_r unexpectedly regenerated")
    end
    -- doc_q should not be regenerated either (its build 3 timestamp should hold)
    if not s4_t4_q then
        return fail("S4 Build 4: doc_q missing output_cache entry")
    end

    -- ========================================================================
    -- SCENARIO 5: Add new document to existing project
    -- ========================================================================

    local s5_proj, s5_dir, s5_out = make_project("s5_add_doc", {"doc_m", "doc_n"})

    write_file(s5_dir .. "/doc_m.md", [[
# SPEC: S5M @SPEC-S5M

## SECTION: Intro @SEC-S5M-001

M content.
]])
    write_file(s5_dir .. "/doc_n.md", [[
# SPEC: S5N @SPEC-S5N

## SECTION: Intro @SEC-S5N-001

N content.
]])

    -- Run 1: build with 2 docs
    local s5r1 = run_project(s5_proj)
    if not s5r1.ok then return fail("S5 Run 1 failed: " .. tostring(s5r1.err)) end

    local s5_t1_m = with_db(s5_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_m", s5_out .. "/doc_m.md")
    end)
    local s5_t1_n = with_db(s5_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_n", s5_out .. "/doc_n.md")
    end)

    sleep_tick()

    -- Add doc_o and update project
    write_file(s5_dir .. "/doc_o.md", [[
# SPEC: S5O @SPEC-S5O

## SECTION: Intro @SEC-S5O-001

O new content.
]])

    -- Update project files to include new doc
    s5_proj.files = {
        s5_dir .. "/doc_m.md",
        s5_dir .. "/doc_n.md",
        s5_dir .. "/doc_o.md"
    }

    -- Run 2: m+n cached, o is new
    local s5r2 = run_project(s5_proj)
    if not s5r2.ok then return fail("S5 Run 2 failed: " .. tostring(s5r2.err)) end

    -- doc_m and doc_n unchanged
    local s5_t2_m = with_db(s5_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_m", s5_out .. "/doc_m.md")
    end)
    local s5_t2_n = with_db(s5_out .. "/specir.db", function(db)
        return output_cache_time(db, "doc_n", s5_out .. "/doc_n.md")
    end)
    if s5_t2_m ~= s5_t1_m then
        return fail("S5: doc_m unexpectedly regenerated after adding new doc")
    end
    if s5_t2_n ~= s5_t1_n then
        return fail("S5: doc_n unexpectedly regenerated after adding new doc")
    end

    -- doc_o generated
    local s5_o_out = read_file(s5_out .. "/doc_o.md")
    if not s5_o_out then
        return fail("S5: new doc_o output was not generated")
    end
    if not contains(s5_o_out, "O new content") then
        return fail("S5: doc_o output has wrong content")
    end

    -- ========================================================================
    -- SCENARIO 6: FTS data completeness after all-cached build
    -- ========================================================================

    local s6_proj, s6_dir, s6_out = make_project("s6_fts", {"doc_f", "doc_g"})

    write_file(s6_dir .. "/doc_f.md", [[
# SPEC: S6F @SPEC-S6F

## SECTION: Alpha @SEC-S6F-001

Unique searchable content from doc F alpha.
]])
    write_file(s6_dir .. "/doc_g.md", [[
# SPEC: S6G @SPEC-S6G

## SECTION: Beta @SEC-S6G-001

Unique searchable content from doc G beta.
]])

    -- Run 1: initial build
    local s6r1 = run_project(s6_proj)
    if not s6r1.ok then return fail("S6 Run 1 failed: " .. tostring(s6r1.err)) end

    -- Check FTS object count for both specs after run 1
    local s6_fts1_f = with_db(s6_out .. "/specir.db", function(db)
        return query_count(db, "SELECT COUNT(*) AS cnt FROM fts_objects WHERE spec_id = :spec", { spec = "doc_f" })
    end)
    local s6_fts1_g = with_db(s6_out .. "/specir.db", function(db)
        return query_count(db, "SELECT COUNT(*) AS cnt FROM fts_objects WHERE spec_id = :spec", { spec = "doc_g" })
    end)

    if not s6_fts1_f or s6_fts1_f == 0 then
        return fail("S6 Run 1: no FTS objects for doc_f")
    end
    if not s6_fts1_g or s6_fts1_g == 0 then
        return fail("S6 Run 1: no FTS objects for doc_g")
    end

    sleep_tick()

    -- Run 2: all cached
    local s6r2 = run_project(s6_proj)
    if not s6r2.ok then return fail("S6 Run 2 failed: " .. tostring(s6r2.err)) end

    -- FTS data must still exist for BOTH specs (not cleared by partial processing)
    local s6_fts2_f = with_db(s6_out .. "/specir.db", function(db)
        return query_count(db, "SELECT COUNT(*) AS cnt FROM fts_objects WHERE spec_id = :spec", { spec = "doc_f" })
    end)
    local s6_fts2_g = with_db(s6_out .. "/specir.db", function(db)
        return query_count(db, "SELECT COUNT(*) AS cnt FROM fts_objects WHERE spec_id = :spec", { spec = "doc_g" })
    end)

    if s6_fts2_f ~= s6_fts1_f then
        return fail(string.format("S6: FTS objects for doc_f changed after cached build (%d -> %d)", s6_fts1_f, s6_fts2_f))
    end
    if s6_fts2_g ~= s6_fts1_g then
        return fail(string.format("S6: FTS objects for doc_g changed after cached build (%d -> %d)", s6_fts1_g, s6_fts2_g))
    end

    -- ========================================================================
    -- SCENARIO 7: Error -> fix -> rebuild (broken doc SECOND)
    -- doc_e is listed FIRST, doc_f (with broken include) is listed SECOND.
    -- This tests the deferred-cache fix: doc_e is processed successfully
    -- before doc_f errors, but its cache hash must NOT be persisted because
    -- the pipeline never ran. On the rebuild, doc_e must be treated as dirty
    -- and processed normally alongside the fixed doc_f.
    -- ========================================================================

    local s7_proj, s7_dir, s7_out = make_project("s7_error_recovery", {"doc_e", "doc_f"})

    write_file(s7_dir .. "/doc_e.md", [[
# SPEC: S7E @SPEC-S7E

## SECTION: Intro @SEC-S7E-001

Doc E content.
]])

    -- doc_f references a missing include (listed SECOND in files array)
    write_file(s7_dir .. "/doc_f.md", [[
# SPEC: S7F @SPEC-S7F

## SECTION: Intro @SEC-S7F-001

```include
includes/missing.md
```
]])

    -- Run 1: should fail (missing include in doc_f, processed second)
    -- doc_e is processed first and succeeds, but its cache MUST NOT be persisted
    local s7r1 = run_project(s7_proj)
    if s7r1.ok then
        return fail("S7 Run 1 should have failed (missing include)")
    end
    if not contains(s7r1.err, "Include file not found") then
        return fail("S7 Run 1 error should mention missing include: " .. tostring(s7r1.err))
    end

    -- Verify doc_e was NOT cached (deferred cache fix)
    local s7_e_cached = with_db(s7_out .. "/specir.db", function(db)
        return query_scalar(db,
            "SELECT sha1 FROM source_files WHERE path = :path",
            { path = s7_dir .. "/doc_e.md" }, "sha1")
    end)
    if s7_e_cached then
        return fail("S7: doc_e hash was persisted despite build failure (deferred cache bug)")
    end

    -- Fix: rewrite doc_f without include
    write_file(s7_dir .. "/doc_f.md", [[
# SPEC: S7F @SPEC-S7F

## SECTION: Intro @SEC-S7F-001

Doc F fixed content.
]])

    -- Run 2: should succeed, both docs processed (both dirty since run 1 never cached them)
    local s7r2 = run_project(s7_proj)
    if not s7r2.ok then return fail("S7 Run 2 failed after fix: " .. tostring(s7r2.err)) end

    -- Both outputs should exist
    local s7_e_out = read_file(s7_out .. "/doc_e.md")
    local s7_f_out = read_file(s7_out .. "/doc_f.md")
    if not s7_e_out then
        return fail("S7: doc_e output missing after error recovery")
    end
    if not s7_f_out then
        return fail("S7: doc_f output missing after error recovery")
    end
    if not contains(s7_e_out, "Doc E content") then
        return fail("S7: doc_e output has wrong content after error recovery")
    end
    if not contains(s7_f_out, "Doc F fixed content") then
        return fail("S7: doc_f output has wrong content after fix")
    end

    return true
end
