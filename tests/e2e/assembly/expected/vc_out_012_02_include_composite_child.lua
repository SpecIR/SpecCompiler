-- Test oracle for VC-OUT-012 (case 02): included composite stays a child.
--
-- The include shift stores the included SECTION at level 3 (child of the
-- level-2 CSU). Rendering and hierarchical PID depth must both anchor to the
-- structural constant (level 2 = depth 1 / heading shift -1), not to the
-- observed minimum over composite objects only -- that re-basing promoted the
-- included section to a sibling of the including object (heading level 1,
-- PID depth 1) whenever no level-2 composite existed in the document.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc
    local suite_dir = helpers.suite_dir .. "/"
    local build_dir = helpers.build_dir .. "/"
    local name = "vc_out_012_02_include_composite_child"
    local out = build_dir .. name .. "_x.json"
    local db = build_dir .. name .. "_x.db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Composite Child Levels" },
        template = "sw_docs",
        files = { suite_dir .. name .. ".md" },
        output_dir = build_dir,
        output_format = "json",
        outputs = {{ format = "json", path = out }},
        db_file = db,
        validation = { traceability_csu_to_fd = "ignore" },
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

    local headers = {}
    doc:walk{
        Header = function(h)
            headers[#headers + 1] = {
                level = h.level,
                id = h.attr.identifier,
                text = pandoc.utils.stringify(h.content),
            }
        end,
    }

    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local by_text = {}
    for _, h in ipairs(headers) do by_text[h.text] = h end

    local csu = by_text["CSU-TIMER: Timer"]
    if not csu then
        err("missing CSU card heading 'CSU-TIMER: Timer'")
    elseif csu.level ~= 1 then
        err("CSU heading level: expected 1, got " .. tostring(csu.level))
    end

    local sec = by_text["Extracted Symbols"]
    if not sec then
        err("missing included section heading 'Extracted Symbols'")
    else
        if sec.level ~= 2 then
            err("included section must be a CHILD (level 2), got level "
                .. tostring(sec.level))
        end
        if sec.id ~= "SDD-CC-sec1.1" then
            err("included section PID depth: expected anchor SDD-CC-sec1.1, got "
                .. tostring(sec.id))
        end
    end

    if #errors > 0 then
        return false, "include composite child:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
