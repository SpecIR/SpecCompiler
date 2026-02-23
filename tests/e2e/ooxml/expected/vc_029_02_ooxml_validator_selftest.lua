-- Test oracle for VC-OOXML-002: Validator Self-Test
-- Generates a valid DOCX, then corrupts copies and verifies the validator
-- correctly detects each type of problem.

return function(_, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Resolve all paths to absolute to avoid issues with os.execute('cd ...')
    local cwd = io.popen("pwd"):read("*l") .. "/"

    -- Derive paths
    local build_dir = helpers.db_file:match("(.+/)")
    local suite_dir = build_dir:gsub("build/$", "")
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
    os.execute(string.format('cp "%s" "%s"', docx_path, corrupt_path))

    -- Extract document.xml, corrupt it, and re-inject
    local h = io.popen(string.format('unzip -p "%s" "word/document.xml" 2>/dev/null', corrupt_path))
    local doc_xml = h and h:read("*a") or ""
    if h then h:close() end

    if doc_xml ~= "" then
        -- Inject unescaped ampersand (the original EMB corruption pattern)
        local corrupted_xml = doc_xml:gsub(
            "</w:body>",
            "<w:p><w:r><w:t>R&D Test</w:t></w:r></w:p></w:body>")

        -- Write corrupted XML, then use zip to replace it in the archive
        -- zip requires the replacement file at the same relative path
        local staging = cwd .. build_dir .. "staging_corrupt"
        os.execute(string.format('mkdir -p "%s/word"', staging))
        local f = io.open(staging .. "/word/document.xml", "w")
        if f then
            f:write(corrupted_xml)
            f:close()
            os.execute(string.format(
                'cd "%s" && zip -q "%s" word/document.xml',
                staging, corrupt_path))
        end
        os.execute(string.format('rm -rf "%s"', staging))

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
    local staging3 = cwd .. build_dir .. "staging_incomplete"
    os.execute(string.format('mkdir -p "%s"', staging3))

    -- Write a minimal [Content_Types].xml
    local ct_f = io.open(staging3 .. "/ct.xml", "w")
    if ct_f then
        ct_f:write('<?xml version="1.0" encoding="UTF-8"?>'
            .. '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            .. '<Default Extension="xml" ContentType="application/xml"/>'
            .. '</Types>')
        ct_f:close()
        -- Create zip with renamed content types (must escape brackets for zip)
        os.execute(string.format(
            'cd "%s" && mv ct.xml "[Content_Types].xml" && zip -q "%s" "[Content_Types].xml"',
            staging3, incomplete_path))
    end
    os.execute(string.format('rm -rf "%s"', staging3))

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
