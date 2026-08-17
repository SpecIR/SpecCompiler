-- Test oracle for VC-OOXML-LO: LibreOffice Round Trip
-- Builds a DOCX with docx.update_fields + docx.export_pdf enabled, letting the
-- default postprocessor drive infra.process.libreoffice. Asserts that the
-- field-updated DOCX is still a valid archive whose bookmarks all resolve
-- (mirroring vc_029_04) and that the exported PDF exists.
--
-- The runner skips this test when LibreOffice/UNO is unavailable.

---Same bookmark integrity check as vc_029_04 (duplicated: oracles are
---standalone dofile'd chunks).
local function check_bookmarks(docx_path, docx_helpers)
    local errors = {}
    local anchors, refs, bookmarks = {}, {}, {}

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
                for name in content:gmatch("%f[%a]REF%s+([%w_%-]+)") do
                    if name ~= "PAGEREF" and refs[name] == nil then refs[name] = part end
                end
                for name in content:gmatch('<w:bookmarkStart[^>]-w:name="([^"]-)"') do
                    bookmarks[name] = true
                end
            end
        end
    end

    for name, part in pairs(anchors) do
        if not bookmarks[name] then
            table.insert(errors, string.format(
                "hyperlink anchor '%s' (%s) has no matching bookmark", name, part))
        end
    end
    for name, part in pairs(refs) do
        if not bookmarks[name] then
            table.insert(errors, string.format(
                "field reference '%s' (%s) has no matching bookmark", name, part))
        end
    end

    return errors
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
    local test_name = "vc_029_05_libreoffice_roundtrip"
    local docx_path = build_dir .. test_name .. ".docx"
    local pdf_path = build_dir .. test_name .. ".pdf"
    local docx_db = build_dir .. "docx_lo_" .. tostring(os.clock()):gsub("%.", "") .. ".db"
    os.remove(pdf_path)

    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_OOXML_LO", name = "LibreOffice round trip" },
        template = "default",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = docx_path }},
        db_file = docx_db,
        docx = { update_fields = true, export_pdf = true },
        logging = { level = "WARN" },
    }

    local gen_ok, gen_err = pcall(engine.run_project, project_info)
    if not gen_ok then
        err("DOCX generation failed: " .. tostring(gen_err))
        return false, table.concat(errors, "\n")
    end

    local docx_helpers = require("docx_helpers")

    -- The field-updated DOCX (LibreOffice re-saved it in place) must still be
    -- a valid archive with resolving bookmarks.
    if not docx_helpers.is_valid_docx(docx_path) then
        err("Field-updated file is not a valid DOCX archive: " .. docx_path)
        return false, table.concat(errors, "\n")
    end
    for _, e in ipairs(check_bookmarks(docx_path, docx_helpers)) do err(e) end

    -- Proof the field update actually ran: the populated TOC repeats the
    -- section titles, so "First Section" appears in at least two text runs
    -- (heading + TOC entry).
    local doc_xml = docx_helpers.get_document_xml(docx_path) or ""
    local title_runs = 0
    for _ in doc_xml:gmatch("<w:t[^>]*>[^<]*First Section") do
        title_runs = title_runs + 1
    end
    if title_runs < 2 then
        err(string.format(
            "Expected 'First Section' in heading and populated TOC (>=2 runs), got %d", title_runs))
    end

    -- PDF export: file exists and is a PDF.
    local pdf = io.open(pdf_path, "rb")
    if not pdf then
        err("LibreOffice PDF was not created: " .. pdf_path)
    else
        local magic = pdf:read(5)
        pdf:close()
        if magic ~= "%PDF-" then
            err("Exported file is not a PDF: " .. pdf_path)
        end
    end

    if #errors > 0 then
        return false, "LibreOffice round trip failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true
end
