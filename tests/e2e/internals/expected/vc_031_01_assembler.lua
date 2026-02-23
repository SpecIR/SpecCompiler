-- Test oracle for VC-INT-011: Document Assembly
-- Verifies document structure, ordering, and float/view inclusion.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Check first block is title Div with SPEC-INT-011 ID
    local first = actual_doc.blocks[1]
    if not first or first.t ~= "Div" then
        err("First block should be spec title Div, got " .. tostring(first and first.t))
    elseif first.identifier ~= "SPEC-INT-011" then
        err("Spec title ID: expected 'SPEC-INT-011', got '" .. tostring(first.identifier) .. "'")
    end

    -- 2. Check headers in order
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

    if #headers < 2 then
        err(string.format("Expected at least 2 section headers, got %d", #headers))
    else
        if headers[1].identifier ~= "SEC-ASM-001" then
            err("First header ID: expected 'SEC-ASM-001', got '" .. tostring(headers[1].identifier) .. "'")
        end
        if headers[2].identifier ~= "SEC-ASM-002" then
            err("Second header ID: expected 'SEC-ASM-002', got '" .. tostring(headers[2].identifier) .. "'")
        end
    end

    -- 3. Check float caption exists
    local caption_found = false
    local function walk_captions(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                for _, cls in ipairs(block.classes or {}) do
                    if cls == "speccompiler-caption" then
                        caption_found = true
                        break
                    end
                end
                walk_captions(block.content)
            end
        end
    end
    walk_captions(actual_doc.blocks)

    if not caption_found then
        err("No float caption found in assembled document")
    end

    -- 4. Attribute-pattern blockquote (doc_version:) is consumed by TRANSFORM,
    -- so verify it does NOT appear as a BlockQuote in output
    local attr_bq_count = 0
    local function walk_bqs(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "BlockQuote" then
                local text = pandoc.utils.stringify(block)
                if text:match("^doc_version:") then
                    attr_bq_count = attr_bq_count + 1
                end
            elseif block.t == "Div" then
                walk_bqs(block.content)
            end
        end
    end
    walk_bqs(actual_doc.blocks)

    if attr_bq_count > 0 then
        err("doc_version blockquote should be consumed by TRANSFORM, but found in output")
    end

    if #errors > 0 then
        return false, "Document assembly validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
