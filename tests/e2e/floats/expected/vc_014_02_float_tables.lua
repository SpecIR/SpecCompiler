-- Test oracle for VC-FLOAT-002: Table Processing
-- Verifies CSV, TSV, and list-table formats are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SPEC-FLOAT-002" then
        err("Spec title ID should be 'SPEC-FLOAT-002'")
    end

    -- 2. Count tables - should have 3 (CSV, TSV, list-table) wrapped in speccompiler-table Divs
    local table_count = 0
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-table" then
                    table_count = table_count + 1
                end
            end
        end
    end

    if table_count ~= 3 then
        err(string.format("Expected 3 speccompiler-table Divs (CSV, TSV, list-table), got %d", table_count))
    end

    -- 3. Count captions - each table should have a caption
    local caption_count = 0
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-caption" then
                    caption_count = caption_count + 1
                end
            end
        end
    end

    if caption_count < 3 then
        err(string.format("Expected at least 3 captions, got %d", caption_count))
    end

    if #errors > 0 then
        return false, "Table processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
