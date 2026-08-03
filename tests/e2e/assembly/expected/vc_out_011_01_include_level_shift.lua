-- Test oracle for VC-OUT-011: Include Heading Level Shift (LLR-071)
--
-- Drives a real DOCX build and asserts the Word Heading styles in document
-- order. Included files are standalone documents starting at `#`; expansion
-- shifts their headings by the level in effect at the include point:
--
--   ## Child Section                    -> Heading1  (main file, level 2)
--   # Parent      (grand_child.md)      -> Heading2  (1 + 2 = 3)
--   ## Child      (grand_child.md)      -> Heading3  (2 + 2 = 4)
--   # Leaf        (great_grand_child.md)-> Heading4  (nested: 1 + 2 + 2 = 5)
--   ## Sibling After                    -> Heading1  (main file, level 2)
--   # Appendix    (appendix.md)         -> Heading1  (`----` pops 2 -> 1, so 1 + 1 = 2)

local docx = require("docx_helpers")

-- Extract (style, text) for every Heading paragraph, in document order.
local function heading_sequence(document_xml)
    local seq = {}
    for para in document_xml:gmatch("<w:p[%s>].-</w:p>") do
        local style = para:match('<w:pStyle w:val="(Heading%d+)"')
        if style then
            local text = {}
            for t in para:gmatch("<w:t[^>]*>(.-)</w:t>") do
                text[#text + 1] = t
            end
            seq[#seq + 1] = { style = style, text = table.concat(text) }
        end
    end
    return seq
end

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) errors[#errors + 1] = msg end

    local build_dir = helpers.build_dir .. "/"
    local suite_dir = helpers.suite_dir .. "/"
    local test_name = "vc_out_011_01_include_level_shift"
    local docx_path = build_dir .. test_name .. ".docx"
    local docx_db = build_dir .. "docx_shift_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Include Level Shift" },
        template = "default",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = docx_path }},
        db_file = docx_db,
        logging = { level = "ERROR" },
    })
    if not ok then
        return false, "DOCX generation failed: " .. tostring(gen_err)
    end

    local document_xml = docx.get_document_xml(docx_path)
    os.remove(docx_db)
    if not document_xml then
        return false, "Could not read word/document.xml from " .. docx_path
    end

    local expected = {
        { style = "Heading1", text = "Child Section" },
        { style = "Heading2", text = "Parent" },
        { style = "Heading3", text = "Child" },
        { style = "Heading4", text = "Leaf" },
        { style = "Heading1", text = "Sibling After" },
        { style = "Heading1", text = "Appendix" },
    }

    local got = heading_sequence(document_xml)

    if #got ~= #expected then
        local lines = {}
        for _, h in ipairs(got) do lines[#lines + 1] = h.style .. " " .. h.text end
        return false, string.format(
            "Expected %d headings, got %d:\n    %s",
            #expected, #got, table.concat(lines, "\n    "))
    end

    for i, want in ipairs(expected) do
        local h = got[i]
        if h.style ~= want.style or h.text ~= want.text then
            err(string.format("Heading %d: expected [%s] '%s' but got [%s] '%s'",
                i, want.style, want.text, h.style, h.text))
        end
    end

    if #errors > 0 then
        return false, "Include level shift mismatch:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
