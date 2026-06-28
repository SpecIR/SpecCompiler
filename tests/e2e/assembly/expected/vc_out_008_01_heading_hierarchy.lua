-- Test oracle for VC-OUT-008: Heading Hierarchy (levels / siblings / children)
--
-- Drives a real DOCX build of a five-file-deep include chain and asserts the
-- resulting Word Heading styles in document order. This pins the end-to-end
-- contract that HLR-OUT-001 calls "adjusts header levels for cross-file
-- includes": the literal markdown level survives include nesting, the assembler
-- rescales the shallowest level to Heading1, and siblings/children/ascents map
-- to the right style.
--
--   ## Chapter A        -> Heading1   (sibling root)
--   ### Section A.1     -> Heading2   (child, +1)
--   #### Subsection ..  -> Heading3   (grandchild, +1, four includes deep)
--   ## Chapter B        -> Heading1   (ascend 4 -> 2: "go back up")
--   ### Section B.1     -> Heading2   (child again)
--   ## Chapter C        -> Heading1   (sibling root, back in main file)

local docx = require("docx_helpers")

-- Extract (style, text) for every Heading paragraph, in document order.
local function heading_sequence(document_xml)
    local seq = {}
    for para in document_xml:gmatch("<w:p[%s>].-</w:p>") do
        local style = para:match('<w:pStyle w:val="(Heading%d)"')
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
    local test_name = "vc_out_008_01_heading_hierarchy"
    local docx_path = build_dir .. test_name .. ".docx"
    local docx_db = build_dir .. "docx_hier_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Heading Hierarchy" },
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
        { style = "Heading1", text = "Chapter A" },
        { style = "Heading2", text = "Section A.1" },
        { style = "Heading3", text = "Subsection A.1.1" },
        { style = "Heading1", text = "Chapter B" },
        { style = "Heading2", text = "Section B.1" },
        { style = "Heading1", text = "Chapter C" },
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
        return false, "Heading hierarchy mismatch:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
