-- Test oracle for VC-REL-001: Reference Link Syntax
-- Verifies traceability links are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end
    local function meta_str(key)
        local val = actual_doc.meta[key]
        if not val then return nil end
        return pandoc.utils.stringify(val)
    end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SRS-REL" then
        err("Spec title ID should be 'SRS-REL'")
    end

    -- 2. Count headers - should have five sequential LLR entries
    local expected_ids = {"LLR-001", "LLR-002", "LLR-003", "LLR-004", "LLR-005"}
    local found_ids = {}

    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Header" then
            table.insert(found_ids, block.identifier)
        end
    end

    if #found_ids ~= #expected_ids then
        err(string.format("Expected %d headers, got %d", #expected_ids, #found_ids))
    end

    -- 3. Check for Link elements (traceability links should be converted)
    local link_count = 0
    local function count_links(blocks)
        for _, block in ipairs(blocks) do
            if block.t == "Div" or block.t == "BlockQuote" then
                count_links(block.content or {})
            elseif block.t == "Para" or block.t == "Plain" then
                for _, inline in ipairs(block.content or {}) do
                    if inline.t == "Link" then
                        link_count = link_count + 1
                    end
                end
            end
        end
    end
    count_links(actual_doc.blocks)

    if link_count < 5 then
        err(string.format("Expected at least 5 traceability links, got %d", link_count))
    end

    if #errors > 0 then
        return false, "Reference link validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
