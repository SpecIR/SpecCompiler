-- Test oracle for VC-SYNTAX-002: Attribute Processing
-- Verifies that attributes are parsed and promoted to metadata correctly
-- Focuses on key structural assertions rather than exact tree matching

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}

    -- Helper to add error
    local function err(msg)
        table.insert(errors, msg)
    end

    -- Helper to get metadata value as string
    local function meta_str(key)
        local val = actual_doc.meta[key]
        if not val then return nil end
        -- MetaInlines is a list of inlines that acts like a Pandoc List
        -- Use pandoc.utils.stringify for reliable conversion
        return pandoc.utils.stringify(val)
    end

    -- 1. Verify document structure
    local expected_blocks = 21
    if #actual_doc.blocks ~= expected_blocks then
        err(string.format("Block count: expected %d, got %d", expected_blocks, #actual_doc.blocks))
    end

    -- 2. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SPEC-ATTR-001" then
        err(string.format("Spec title ID: expected 'SPEC-ATTR-001', got '%s'", title_block.identifier))
    end

    -- 3. Verify metadata attributes from document-level blockquotes
    local expected_meta = {
        string_attr = "Simple string value",
        integer_attr = "42",
        boolean_attr = "true",
        date_attr = "2025-01-05",
    }

    for key, expected_val in pairs(expected_meta) do
        local actual_val = meta_str(key)
        if actual_val ~= expected_val then
            err(string.format("Meta '%s': expected '%s', got '%s'", key, expected_val, actual_val or "nil"))
        end
    end

    -- 4. Verify section headers exist with correct IDs
    local expected_headers = {
        {id = "SEC-MULTI", level = 1},
        {id = "SEC-CAST-WRONG", level = 1},  -- First SEC-CAST (WRONG)
        {id = "SEC-CAST", level = 1},  -- Second SEC-CAST (FIX)
        {id = "SEC-INLINE-MULTI", level = 1},
    }

    local header_idx = 1
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Header" then
            local expected = expected_headers[header_idx]
            if expected then
                if block.identifier ~= expected.id then
                    err(string.format("Header %d ID: expected '%s', got '%s'", header_idx, expected.id, block.identifier))
                end
                if block.level ~= expected.level then
                    err(string.format("Header %d level: expected %d, got %d", header_idx, expected.level, block.level))
                end
                header_idx = header_idx + 1
            end
        end
    end

    if header_idx - 1 ~= #expected_headers then
        err(string.format("Header count: expected %d, got %d", #expected_headers, header_idx - 1))
    end

    -- 5. Verify section-level metadata was extracted
    -- The Type Casting (FIX) section has separate attributes
    local section_meta = {
        count = "100",
        enabled = "false",
        ratio = "0.75",
        created = "2024-12-01",
    }

    for key, expected_val in pairs(section_meta) do
        local actual_val = meta_str(key)
        if actual_val ~= expected_val then
            err(string.format("Section meta '%s': expected '%s', got '%s'", key, expected_val, actual_val or "nil"))
        end
    end

    -- Return result
    if #errors > 0 then
        return false, "Attribute processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    return true, nil
end
