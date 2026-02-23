-- Test oracle for VC-REQIF-001: ReqIF Export Validity
-- Generates ReqIF output and validates the archive structure.
--
-- Checks: well-formedness, required structure, referential integrity,
-- content assertions (PIDs, relations, XHTML, enum datatypes, object types),
-- and Python reqif library roundtrip.

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Sanity check: AST should have content
    if not actual_doc or #actual_doc.blocks < 1 then
        err("Document AST should have blocks")
        return false, table.concat(errors, "\n")
    end

    -- Derive paths from db_file (tests/e2e/reqif/build/specir.db)
    local build_dir = helpers.db_file:match("(.+/)")
    local suite_dir = build_dir:gsub("build/$", "")
    local test_name = "vc_028_03_reqif_export"
    local reqif_path = build_dir .. test_name .. ".reqif"

    -- Use a separate, timestamped DB to avoid SQLite locking conflicts
    local reqif_db = build_dir .. "reqif_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    -- Generate ReqIF output using speccompiler engine
    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_REQIF", name = "ReqIF Export Tests" },
        template = "sw_docs",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "reqif",
        outputs = {{ format = "reqif", path = reqif_path }},
        db_file = reqif_db,
        logging = { level = "WARN" },
        validation = { traceability_hlr_to_vc = "ignore" },
    }

    local gen_ok, gen_err = pcall(engine.run_project, project_info)
    if not gen_ok then
        err("ReqIF generation failed: " .. tostring(gen_err))
        -- Clean up
        os.remove(reqif_db)
        os.remove(reqif_db .. "-wal")
        os.remove(reqif_db .. "-shm")
        return false, table.concat(errors, "\n")
    end

    -- Verify file was created
    local f = io.open(reqif_path, "r")
    if not f then
        err("ReqIF file was not created: " .. reqif_path)
        os.remove(reqif_db)
        os.remove(reqif_db .. "-wal")
        os.remove(reqif_db .. "-shm")
        return false, table.concat(errors, "\n")
    end
    f:close()

    -- Run ReqIF validation
    local validator = require("reqif_validator")
    local valid, validation_errors = validator.validate_reqif(reqif_path, {
        -- Structural: 4 objects (SF-REQIF, HLR-REQIF-001, HLR-REQIF-002, SYMBOL-REQIF)
        min_spec_objects = 4,
        -- Relations: belongs_to + traceability
        min_relations = 2,
        -- PIDs present as attribute values
        expect_pids = {"SF-REQIF", "HLR-REQIF-001", "HLR-REQIF-002", "SYMBOL-REQIF"},
        -- XHTML content (rich text in body/attributes)
        expect_xhtml = true,
        -- Enum datatypes from sw_docs model
        expect_enum_datatypes = {"TRACEABLE_status", "HLR_priority"},
        -- Object types (long_name from spec_object_types table)
        expect_object_type_names = {"Software Function", "High-Level Requirement", "Code Symbol"},
    })

    if not valid then
        for _, ve in ipairs(validation_errors) do
            err(ve)
        end
    end

    -- Clean up ephemeral DB
    os.remove(reqif_db)
    os.remove(reqif_db .. "-wal")
    os.remove(reqif_db .. "-shm")

    if #errors > 0 then
        return false, "ReqIF validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
