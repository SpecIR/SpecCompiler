-- Test oracle for VC-OUT-011: Include Level Shift combinations.
--
-- Drives a real DOCX build and asserts the Word Heading styles in document
-- order across shift combinations (levels are pre-normalization; the
-- assembler rescales the shallowest, 2, to Heading1):
--
--   ## Alpha                                  -> Heading1  (2)
--   # Multi One        (multi_section.md)     -> Heading2  (1+2=3)
--   ## Multi One A     (multi_section.md)     -> Heading3  (2+2=4)
--   ### Multi One A I  (multi_section.md)     -> Heading4  (3+2=5)
--   # Multi Two        (multi_section.md)     -> Heading2  (ascend inside file)
--   ## Multi Two A     (multi_section.md)     -> Heading3
--   (prose_only.md contributes no headings)
--   # Sibling Inc      (sibling.md)           -> Heading2  (same block, same shift)
--   ## Sibling Inc A   (sibling.md)           -> Heading3
--   ### Alpha Deep                            -> Heading2  (3, authored in main)
--   # Deep Leaf        (deep_leaf.md)         -> Heading3  (1+3=4)
--   # After Close      (after_close.md)       -> Heading2  (`----` pops 3->2, 1+2=3)
--   # New Chapter      (after_double_close.md)-> Heading1  (second `----` pops 2->1, 1+1=2)
--   ## Omega                                  -> Heading1  (2)
--   # Close One        (internal_close.md)    -> Heading2  (1+2=3)
--   ## Close One A     (internal_close.md)    -> Heading3  (2+2=4)
--   # Inner Leaf       (inner_leaf.md)        -> Heading3  (internal `----` pops 2->1, 1+1=2, +2 outer=4)
--   # Close Two        (internal_close.md)    -> Heading2  (ascend inside file)

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
    local test_name = "vc_out_011_02_include_level_combos"
    local docx_path = build_dir .. test_name .. ".docx"
    local docx_db = build_dir .. "docx_combo_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local ok, gen_err = pcall(engine.run_project, {
        project = { code = "TEST_ASSEMBLY", name = "Include Level Combos" },
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
        { style = "Heading1", text = "Alpha" },
        { style = "Heading2", text = "Multi One" },
        { style = "Heading3", text = "Multi One A" },
        { style = "Heading4", text = "Multi One A I" },
        { style = "Heading2", text = "Multi Two" },
        { style = "Heading3", text = "Multi Two A" },
        { style = "Heading2", text = "Sibling Inc" },
        { style = "Heading3", text = "Sibling Inc A" },
        { style = "Heading2", text = "Alpha Deep" },
        { style = "Heading3", text = "Deep Leaf" },
        { style = "Heading2", text = "After Close" },
        { style = "Heading1", text = "New Chapter" },
        { style = "Heading1", text = "Omega" },
        { style = "Heading2", text = "Close One" },
        { style = "Heading3", text = "Close One A" },
        { style = "Heading3", text = "Inner Leaf" },
        { style = "Heading2", text = "Close Two" },
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
        return false, "Include level combos mismatch:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
