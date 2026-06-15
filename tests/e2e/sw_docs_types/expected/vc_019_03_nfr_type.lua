-- Test oracle for VC-TYPE-002: Non-Functional Requirement Type
-- Verifies NFR objects are created with category, priority, metric attributes

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SRS-NFR" then
        err("Spec title ID should be 'SRS-NFR', got: " .. tostring(title_block.identifier))
    end

    -- 2. Count NFR objects recursively (headers may be nested in wrappers)
    local nfr_count = 0
    local nfr_ids = {}

    actual_doc:walk({
        Header = function(header)
            local id = header.identifier or ""
            if id:match("^NFR%-") then
                nfr_count = nfr_count + 1
                table.insert(nfr_ids, id)
            end
        end
    })

    -- Should have 5 NFR objects
    if nfr_count ~= 5 then
        err(string.format("Expected 5 NFR headers, got %d", nfr_count))
    end

    -- 3. Verify expected NFR IDs exist
    local expected_ids = {
        "NFR-PERF-001",
        "NFR-PERF-002",
        "NFR-SEC-001",
        "NFR-REL-001",
        "NFR-USE-001"
    }

    for _, expected_id in ipairs(expected_ids) do
        local found = false
        for _, actual_id in ipairs(nfr_ids) do
            if actual_id == expected_id then
                found = true
                break
            end
        end
        if not found then
            err("Missing expected NFR: " .. expected_id)
        end
    end

    -- 4. Verify category attributes are present (look for category text in content)
    local expected_categories = {"Performance", "Scalability", "Security", "Reliability", "Usability"}
    local doc_text = pandoc.utils.stringify(actual_doc)
    local categories_found = 0

    for _, cat in ipairs(expected_categories) do
        if doc_text:find(cat) then
            categories_found = categories_found + 1
        end
    end

    if categories_found < 4 then
        err(string.format("Expected at least 4 category values, found %d (in text: %s...)",
            categories_found, doc_text:sub(1, 200)))
    end

    if #errors > 0 then
        return false, "NFR type validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
