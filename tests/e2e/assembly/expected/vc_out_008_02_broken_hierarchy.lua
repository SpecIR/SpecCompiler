-- Test oracle for VC-OUT-008: Broken heading hierarchy detection.
--
-- The verification view `object_broken_hierarchy` must reject structurally
-- invalid documents BEFORE they reach the renderer (where a silent miscompute
-- produces e.g. a subsection numbered as a chapter). This oracle builds each
-- fixture under fixtures/ and asserts the diagnostic fired (or not):
--
--   skip.md           -> skipped level (## then ####)            : flagged
--   orphan.md         -> opens deeper than its shallowest heading : flagged
--   orphan_include.md -> same, but the chapter is one include deep : flagged
--   valid.md          -> contiguous multi-level + ascend          : clean
--
-- This is a self-driving oracle: the suite runs in normal mode, so the primary
-- doc is trivially valid and `actual_doc` is ignored.

local CODE = "object_broken_hierarchy"

-- Build a fixture and return how many `object_broken_hierarchy` diagnostics
-- fired, plus their concatenated messages.
local function broken_count(suite_dir, build_dir, name)
    local engine = require("core.engine")
    local db = build_dir .. "fix_" .. name:gsub("%.md$", "") .. "_"
        .. tostring(os.clock()):gsub("%.", "") .. ".db"
    local ok, diag = pcall(engine.run_project, {
        project = { code = "TEST_HIER", name = "hier fixture" },
        template = "default",
        files = { suite_dir .. "fixtures/" .. name },
        output_dir = build_dir,
        output_format = "json",
        db_file = db,
        logging = { level = "ERROR" },
    })
    os.remove(db)
    if not ok then
        -- A thrown error still carries the diagnostic in its text; treat the
        -- presence of the code as a hit so the build-abort path is covered.
        return select(2, pcall(function() return tostring(diag):find(CODE) and 1 or 0 end)) or 0, tostring(diag)
    end

    local n, msgs = 0, {}
    for _, e in ipairs((diag and diag.errors) or {}) do
        if e.code == CODE then n = n + 1; msgs[#msgs + 1] = e.message or "" end
    end
    for _, w in ipairs((diag and diag.warnings) or {}) do
        if w.code == CODE then n = n + 1; msgs[#msgs + 1] = w.message or "" end
    end
    return n, table.concat(msgs, " | ")
end

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) errors[#errors + 1] = msg end

    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"

    -- Each broken fixture must produce at least one diagnostic; the message
    -- must name the defect we expect.
    local skip_n, skip_msg = broken_count(suite_dir, build_dir, "skip.md")
    if skip_n < 1 then err("skip.md: expected a skipped-level diagnostic, got none")
    elseif not skip_msg:find("skipping level") then
        err("skip.md: diagnostic did not describe a skipped level: " .. skip_msg)
    end

    local orphan_n, orphan_msg = broken_count(suite_dir, build_dir, "orphan.md")
    if orphan_n < 1 then err("orphan.md: expected an orphan-root diagnostic, got none")
    elseif not orphan_msg:find("orphaned") then
        err("orphan.md: diagnostic did not describe an orphaned root: " .. orphan_msg)
    end

    local orphinc_n = broken_count(suite_dir, build_dir, "orphan_include.md")
    if orphinc_n < 1 then
        err("orphan_include.md: expected a diagnostic when the chapter is one include deep, got none")
    end

    -- An empty heading (the empty-`##` "section reset" hack) renders as a blank
    -- numbered chapter and corrupts numbering; it must be rejected.
    local empty_n, empty_msg = broken_count(suite_dir, build_dir, "empty_heading.md")
    if empty_n < 1 then err("empty_heading.md: expected an empty-title diagnostic, got none")
    elseif not empty_msg:find("no title") then
        err("empty_heading.md: diagnostic did not describe an empty title: " .. empty_msg)
    end

    -- The valid control must stay clean — no false positives.
    local valid_n, valid_msg = broken_count(suite_dir, build_dir, "valid.md")
    if valid_n > 0 then
        err("valid.md: false positive — contiguous multi-level + ascend was flagged: " .. valid_msg)
    end

    if #errors > 0 then
        return false, "Broken-hierarchy detection failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
