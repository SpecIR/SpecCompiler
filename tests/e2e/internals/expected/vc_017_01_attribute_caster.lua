-- Test oracle for VC-INT-008: Attribute Casting
-- Verifies that blockquote attributes matching key: value pattern are consumed
-- by the pipeline (stripped during TRANSFORM) even when unregistered.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Verify document has a spec title Div
    local first = actual_doc.blocks[1]
    if not first or first.t ~= "Div" then
        err("First block should be spec title Div, got " .. tostring(first and first.t))
    elseif first.identifier ~= "SPEC-INT-008" then
        err("Spec title ID: expected 'SPEC-INT-008', got '" .. tostring(first.identifier) .. "'")
    end

    -- Attribute-pattern blockquotes (key: value) are consumed by the TRANSFORM
    -- phase via filter_attribute_blockquotes(), so they should NOT appear in output.
    local blockquotes = {}
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "BlockQuote" then
                table.insert(blockquotes, block)
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if #blockquotes > 0 then
        local keys = {}
        for _, bq in ipairs(blockquotes) do
            table.insert(keys, pandoc.utils.stringify(bq):sub(1, 30))
        end
        err(string.format("Expected 0 BlockQuotes (attribute pattern consumed), got %d: %s",
            #blockquotes, table.concat(keys, ", ")))
    end

    -- Verify section header exists
    local headers = {}
    local function walk_headers(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Header" then
                table.insert(headers, block)
            elseif block.t == "Div" then
                walk_headers(block.content)
            end
        end
    end
    walk_headers(actual_doc.blocks)

    if #headers < 1 then
        err("Expected at least 1 section header")
    elseif headers[1].identifier ~= "VC-INT-008" then
        err("Section header ID: expected 'VC-INT-008', got '" .. tostring(headers[1].identifier) .. "'")
    end

    -- Verify content paragraph survives
    local doc_text = pandoc.utils.stringify(actual_doc)
    if not doc_text:find("specification%-level attributes") then
        err("Content paragraph text not found in output")
    end

    if #errors > 0 then
        return false, "Attribute casting validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
