-- Test oracle for VC-OUT-012 (case 03): hierarchical PIDs per type.
--
-- Hierarchical PID generation must respect the type's own pid_prefix and keep
-- one counter chain PER TYPE: an EXEC_SUMMARY between two SECTIONs numbers in
-- its own `exec` chain instead of consuming a `sec` slot. Depth anchors to the
-- structural constant (level 2 = depth 1). A generated PID colliding with an
-- explicit author PID bumps the counter instead of duplicating it.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc
    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"
    local name = "vc_out_012_03_hierarchical_pid_per_type"
    local out = build_dir .. name .. "_x.json"
    local db = build_dir .. name .. "_x.db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Per Type Hierarchical PIDs" },
        template = "default",
        files = { suite_dir .. name .. ".md" },
        output_dir = build_dir,
        output_format = "json",
        outputs = {{ format = "json", path = out }},
        db_file = db,
        logging = { level = "ERROR" },
    })
    os.remove(db)
    if not ok then
        return false, "build failed: " .. tostring(gen_err)
    end

    local f = io.open(out, "r")
    if not f then return false, "missing json output: " .. out end
    local content = f:read("*a")
    f:close()
    local doc = pandoc.read(content, "json")

    local by_text = {}
    doc:walk{
        Header = function(h)
            by_text[pandoc.utils.stringify(h.content)] = {
                level = h.level,
                id = h.attr.identifier,
                unnumbered = h.attr.classes:includes("unnumbered"),
            }
        end,
    }

    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local expected = {
        { text = "Introduction",  id = "MAN-PIDS-sec1" },
        { text = "Summary",       id = "MAN-PIDS-exec1" },
        { text = "Details",       id = "MAN-PIDS-sec2" },
        { text = "Sub Detail",    id = "MAN-PIDS-sec2.1" },
        { text = "Legacy Notes",  id = "MAN-PIDS-sec3" },
        { text = "Final Remarks", id = "MAN-PIDS-sec4" },
    }

    for _, want in ipairs(expected) do
        local h = by_text[want.text]
        if not h then
            err("missing heading '" .. want.text .. "'")
        elseif h.id ~= want.id then
            err(string.format("'%s': expected anchor %s, got %s",
                want.text, want.id, tostring(h.id)))
        end
    end

    local summary = by_text["Summary"]
    if summary and not summary.unnumbered then
        err("EXEC_SUMMARY declares unnumbered=true; heading must carry the class")
    end

    if #errors > 0 then
        return false, "per-type hierarchical PIDs:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
