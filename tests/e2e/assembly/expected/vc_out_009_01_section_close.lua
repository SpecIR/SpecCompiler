-- Test oracle for VC-OUT-009: Section Scope Termination (`----` close).
--
-- A `----` thematic break closes the current section's scope:
--   * the closed section's end_line truncates at the body before the marker
--     (so trailing content is contained by the parent, not the section),
--   * the marker is consumed (no horizontal rule in the DOCX),
--   * content after the marker keeps its document position.
--
-- Section A spans lines 5-7 (header + "Body of A before the rule."); the `----`
-- is on line 9 and "Trailing content..." on line 11. With the close, Section A's
-- end_line must stop before the rule (< line 9), not extend to Section B (line 13).

local docx = require("docx_helpers")

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) errors[#errors + 1] = msg end

    local build_dir = helpers.build_dir .. "/"
    local suite_dir = helpers.suite_dir .. "/"
    local test_name = "vc_out_009_01_section_close"
    local docx_path = build_dir .. test_name .. ".docx"
    local db_path = build_dir .. "close_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Section Close" },
        template = "default",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = docx_path }},
        db_file = db_path,
        logging = { level = "ERROR" },
    })
    if not ok then
        return false, "Build failed (the `----` close must not error): " .. tostring(gen_err)
    end

    -- 1. Scope: Section A's end_line truncates at the marker (< line 9), not at
    --    Section B (line 13).
    local sqlite = require("lsqlite3")
    local db = sqlite.open(db_path)
    local a_end, b_start
    for r in db:nrows("SELECT title_text, start_line, end_line FROM spec_objects") do
        if r.title_text == "Section A" then a_end = r.end_line end
        if r.title_text == "Section B" then b_start = r.start_line end
    end
    db:close()
    os.remove(db_path)

    if not a_end then
        err("Section A not found in IR")
    elseif a_end >= 9 then
        err(string.format("Section A end_line (%d) did not truncate at the `----` (line 9); "
            .. "scope was not closed by the marker", a_end))
    end
    if b_start and a_end and a_end >= b_start then
        err("Section A scope leaked past Section B")
    end

    -- 2. The marker is consumed: no horizontal-rule border paragraph in the DOCX.
    local xml = docx.get_document_xml(docx_path)
    if not xml then
        return false, "Could not read document.xml"
    end
    if xml:find("<w:pBdr>") then
        err("A horizontal-rule border was emitted — the `----` marker was not consumed")
    end

    -- 3. Trailing content after the marker still renders, in order.
    local before_pos = xml:find("Body of A before the rule", 1, true)
    local trailing_pos = xml:find("Trailing content after the rule", 1, true)
    local section_b_pos = xml:find("Section B", 1, true)
    if not trailing_pos then
        err("Content after the `----` was dropped from the output")
    end
    if not before_pos then
        err("Content before the `----` was dropped from the output")
    end
    if before_pos and trailing_pos and before_pos >= trailing_pos then
        err("Content after the `----` rendered before the section content it follows")
    end
    if trailing_pos and section_b_pos and trailing_pos >= section_b_pos then
        err("Trailing parent content should render before Section B")
    end

    if #errors > 0 then
        return false, "Section close validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
