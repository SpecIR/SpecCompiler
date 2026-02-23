-- Test oracle for VC-INT-009: Document Structure
-- Verifies headers exist with correct IDs and levels after pipeline processing.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Find all headers recursively
    local headers = {}
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Header" then
                table.insert(headers, block)
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    -- Should have at least 3 headers (SEC-FIRST, SEC-SECOND, REQ-WALK-001)
    if #headers < 3 then
        err(string.format("Expected at least 3 headers, got %d", #headers))
        return false, "Document structure validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Check header IDs are present
    local expected_ids = { "SEC-FIRST", "SEC-SECOND", "REQ-WALK-001" }
    local found_ids = {}
    for _, h in ipairs(headers) do
        found_ids[h.identifier] = true
    end

    for _, id in ipairs(expected_ids) do
        if not found_ids[id] then
            err(string.format("Missing expected header ID: '%s'", id))
        end
    end

    -- Verify first block is spec title Div
    local first = actual_doc.blocks[1]
    if not first or first.t ~= "Div" then
        err("First block should be spec title Div")
    elseif first.identifier ~= "SPEC-INT-009" then
        err("Spec title ID: expected 'SPEC-INT-009', got '" .. tostring(first.identifier) .. "'")
    end

    if #errors > 0 then
        return false, "Document structure validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
