-- Test oracle for VC-OOXML-001: DOCX Structural Validity
-- Generates DOCX output and validates the archive structure.
--
-- Checks: well-formedness, required parts, relationship consistency,
-- content type coverage, and namespace declarations.

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Sanity check: AST should have content
    if not actual_doc or #actual_doc.blocks < 1 then
        err("Document AST should have blocks")
        return false, table.concat(errors, "\n")
    end

    -- Derive paths from db_file (tests/e2e/ooxml/build/specir.db)
    local build_dir = helpers.db_file:match("(.+/)")
    local suite_dir = build_dir:gsub("build/$", "")
    local test_name = "vc_029_01_ooxml_schema_validation"
    local docx_path = build_dir .. test_name .. ".docx"

    -- Use a separate, timestamped DB for DOCX generation to avoid SQLite
    -- locking conflicts with the runner's DB on consecutive runs.
    local docx_db = build_dir .. "docx_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    -- Generate DOCX output using speccompiler engine
    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_OOXML", name = "OOXML Validation Tests" },
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

    -- Verify file was created
    local f = io.open(docx_path, "r")
    if not f then
        err("DOCX file was not created: " .. docx_path)
        return false, table.concat(errors, "\n")
    end
    f:close()

    -- Run OOXML validation
    local validator = require("ooxml_validator")
    local valid, validation_errors = validator.validate_docx(docx_path)

    if not valid then
        for _, ve in ipairs(validation_errors) do
            err(ve)
        end
    end

    -- Clean up ephemeral DB
    os.remove(docx_db)

    if #errors > 0 then
        return false, "OOXML validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
