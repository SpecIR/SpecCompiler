-- Test oracle for VC-FLOAT-001: Float Syntax and Numbering
-- Verifies that different float types are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SPEC-FLOAT-001" then
        err("Spec title ID should be 'SPEC-FLOAT-001'")
    end

    -- 2. Count float-related structures (captions, tables, etc)
    local caption_count = 0
    local table_div_count = 0
    local rawblock_count = 0
    local codeblock_count = 0

    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-caption" then
                    caption_count = caption_count + 1
                elseif cls == "speccompiler-table" then
                    table_div_count = table_div_count + 1
                end
            end
        elseif block.t == "RawBlock" then
            rawblock_count = rawblock_count + 1
        elseif block.t == "CodeBlock" then
            codeblock_count = codeblock_count + 1
        end
    end

    -- Should have captions for floats
    if caption_count < 3 then
        err(string.format("Expected at least 3 captions, got %d", caption_count))
    end

    -- Should have speccompiler-table div from CSV processing
    if table_div_count < 1 then
        err("Expected at least 1 speccompiler-table div from CSV processing")
    end

    -- Should have code blocks for listing
    if codeblock_count < 1 then
        err("Expected at least 1 code block")
    end

    -- 3. Verify headers exist
    local header_count = 0
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Header" then
            header_count = header_count + 1
        end
    end

    if header_count < 4 then
        err(string.format("Expected at least 4 headers, got %d", header_count))
    end

    if #errors > 0 then
        return false, "Float syntax validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
