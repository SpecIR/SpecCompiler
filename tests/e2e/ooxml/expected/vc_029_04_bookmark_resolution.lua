-- Test oracle for VC-OOXML-BMK: Bookmark Resolution
-- Builds the DOCX (through the full postprocessor chain), unzips it, and
-- asserts that every hyperlink anchor (w:anchor) and every field reference
-- (PAGEREF/REF instrText) across the word/*.xml parts has a matching
-- w:bookmarkStart. Unresolved references are what Word/LibreOffice render
-- as "Error: Reference source not found" after a field update.

---Collect anchors, field refs and bookmark names from all word/*.xml parts.
---Shared with the LibreOffice round-trip oracle via the module pattern below.
local function check_bookmarks(docx_path, docx_helpers)
    local errors = {}
    local anchors = {}    -- name -> first part it appeared in
    local refs = {}       -- name -> first part it appeared in
    local bookmarks = {}  -- name -> true

    for _, part in ipairs(docx_helpers.list_files(docx_path)) do
        if part:match("^word/[^/]+%.xml$") then
            local content = docx_helpers.extract_from_docx(docx_path, part)
            if content then
                for name in content:gmatch('[<%s]w:anchor="([^"]+)"') do
                    if anchors[name] == nil then anchors[name] = part end
                end
                for name in content:gmatch("PAGEREF%s+([%w_%-]+)") do
                    if refs[name] == nil then refs[name] = part end
                end
                -- %f[%a] keeps plain REF from re-matching the tail of PAGEREF
                for name in content:gmatch("%f[%a]REF%s+([%w_%-]+)") do
                    if name ~= "PAGEREF" and refs[name] == nil then refs[name] = part end
                end
                for name in content:gmatch('<w:bookmarkStart[^>]-w:name="([^"]-)"') do
                    bookmarks[name] = true
                end
            end
        end
    end

    local anchor_count, ref_count = 0, 0
    for name, part in pairs(anchors) do
        anchor_count = anchor_count + 1
        if not bookmarks[name] then
            table.insert(errors, string.format(
                "hyperlink anchor '%s' (%s) has no matching bookmark", name, part))
        end
    end
    for name, part in pairs(refs) do
        ref_count = ref_count + 1
        if not bookmarks[name] then
            table.insert(errors, string.format(
                "field reference '%s' (%s) has no matching bookmark", name, part))
        end
    end

    return errors, anchor_count, ref_count
end

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if not actual_doc or #actual_doc.blocks < 1 then
        err("Document AST should have blocks")
        return false, table.concat(errors, "\n")
    end

    local build_dir = helpers.build_dir .. "/"
    local suite_dir = helpers.suite_dir .. "/"
    local test_name = "vc_029_04_bookmark_resolution"
    local docx_path = build_dir .. test_name .. ".docx"
    local docx_db = build_dir .. "docx_bmk_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_OOXML_BMK", name = "Bookmark resolution" },
        template = "default",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = docx_path }},
        db_file = docx_db,
        logging = { level = "WARN" },
    }

    local gen_ok, gen_err = pcall(engine.run_project, project_info)
    if not gen_ok then
        err("DOCX generation failed: " .. tostring(gen_err))
        return false, table.concat(errors, "\n")
    end

    local docx_helpers = require("docx_helpers")
    if not docx_helpers.is_valid_docx(docx_path) then
        err("Generated file is not a valid DOCX archive: " .. docx_path)
        return false, table.concat(errors, "\n")
    end

    local bmk_errors, anchor_count = check_bookmarks(docx_path, docx_helpers)
    for _, e in ipairs(bmk_errors) do err(e) end

    -- Guard against a vacuous pass: the fixture links to sections, floats and
    -- table-cell targets, so a healthy build has several anchors. (No PAGEREF
    -- floor: the TOC field is dynamic — PAGEREFs appear only after a field
    -- update, which the LibreOffice round-trip test covers.)
    if anchor_count < 5 then
        err(string.format("Expected at least 5 hyperlink anchors, got %d", anchor_count))
    end

    if #errors > 0 then
        return false, "Bookmark resolution failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
