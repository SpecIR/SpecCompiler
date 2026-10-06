-- Test oracle for VC-OOXML-002: Validator Self-Test
-- Generates a valid DOCX, then corrupts copies and verifies the validator
-- correctly detects each type of problem.

return function(_, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Resolve all paths to absolute
    local cwd = pandoc.system.get_working_directory():gsub("[/\\]$", "") .. "/"

    local function read_bytes(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local data = f:read("*a")
        f:close()
        return data
    end
    local function write_archive(path, entries)
        local f = assert(io.open(path, "wb"))
        f:write(pandoc.zip.Archive(entries):bytestring())
        f:close()
    end

    local build_dir = helpers.build_dir .. "/"
    local suite_dir = helpers.suite_dir .. "/"
    local test_name = "vc_029_02_ooxml_validator_selftest"
    local docx_path = cwd .. build_dir .. test_name .. ".docx"
    local docx_db = cwd .. build_dir .. "selftest_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    -- Generate DOCX output
    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_OOXML", name = "OOXML Validator Self-Test" },
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

    local validator = require("ooxml_validator")

    -- ================================================================
    -- Test 1: Valid DOCX should pass all checks
    -- ================================================================
    local valid, validation_errors = validator.validate_docx(docx_path)
    if not valid then
        for _, ve in ipairs(validation_errors) do
            err("Valid DOCX failed validation: " .. ve)
        end
        return false, "OOXML validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- ================================================================
    -- Test 2: Malformed XML detection
    -- ================================================================
    -- Create a corrupted copy with broken XML in document.xml
    local corrupt_path = cwd .. build_dir .. "corrupt_wellformed.docx"

    -- Extract document.xml, corrupt it, and re-inject
    local kept_entries = {}
    local doc_xml = ""
    for _, entry in ipairs(pandoc.zip.Archive(read_bytes(docx_path) or "").entries) do
        if entry.path == "word/document.xml" then
            doc_xml = entry:contents()
        else
            table.insert(kept_entries, entry)
        end
    end

    if doc_xml ~= "" then
        -- Inject unescaped ampersand (the original EMB corruption pattern)
        local corrupted_xml = doc_xml:gsub(
            "</w:body>",
            "<w:p><w:r><w:t>R&D Test</w:t></w:r></w:p></w:body>")

        -- Replace document.xml in a copy of the archive
        table.insert(kept_entries, pandoc.zip.Entry("word/document.xml", corrupted_xml))
        write_archive(corrupt_path, kept_entries)

        local wf_ok = validator.validate_wellformedness(corrupt_path)
        if wf_ok then
            err("Test 2 FAILED: validator did not detect malformed XML (unescaped &)")
        end

        os.remove(corrupt_path)
    end

    -- ================================================================
    -- Test 3: Missing required parts detection
    -- ================================================================
    local incomplete_path = cwd .. build_dir .. "incomplete.docx"

    -- An archive holding only a minimal [Content_Types].xml
    write_archive(incomplete_path, {
        pandoc.zip.Entry("[Content_Types].xml", '<?xml version="1.0" encoding="UTF-8"?>'
            .. '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            .. '<Default Extension="xml" ContentType="application/xml"/>'
            .. '</Types>')
    })

    local rp_ok, rp_errors = validator.validate_required_parts(incomplete_path)
    if rp_ok then
        err("Test 3 FAILED: validator did not detect missing required parts")
    else
        local found_missing = false
        for _, e in ipairs(rp_errors) do
            if e:match("Missing required part") then
                found_missing = true
                break
            end
        end
        if not found_missing then
            err("Test 3 FAILED: errors don't mention missing required parts")
        end
    end
    os.remove(incomplete_path)

    -- ================================================================
    -- Test 4: Nonexistent file detection
    -- ================================================================
    local ne_ok = validator.validate_docx(cwd .. build_dir .. "nonexistent.docx")
    if ne_ok then
        err("Test 4 FAILED: validator did not detect nonexistent file")
    end

    -- ================================================================
    -- Clean up ephemeral DB
    -- ================================================================
    os.remove(docx_db)

    if #errors > 0 then
        return false, "Validator self-test failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
