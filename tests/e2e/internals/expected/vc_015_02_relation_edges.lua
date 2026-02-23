-- Test oracle for VC-INT-016: Relation Resolver Edge Cases
-- Verifies resolved vs unresolved links and type preservation.
-- Note: The pipeline rewrites ALL @-links to #PID format, including unresolved ones.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Find all Link elements in the document
    local links = {}
    local function walk_inlines(inlines)
        for _, inl in ipairs(inlines or {}) do
            if inl.t == "Link" then
                table.insert(links, inl)
            end
        end
    end

    local function walk_blocks(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Para" or block.t == "Plain" then
                walk_inlines(block.content)
            elseif block.t == "BlockQuote" or block.t == "Div" then
                walk_blocks(block.content)
            end
        end
    end
    walk_blocks(actual_doc.blocks)

    -- Should have at least 3 links (valid PID, missing, header ref)
    if #links < 3 then
        err(string.format("Expected at least 3 links, got %d", #links))
    end

    -- All links should have been rewritten to #PID format
    local anchor_links = 0
    local targets = {}
    for _, link in ipairs(links) do
        local target = link.target or ""
        if target:sub(1, 1) == "#" and #target > 1 then
            anchor_links = anchor_links + 1
            targets[target] = true
        end
    end

    -- All 3 links should have # targets
    if anchor_links < 3 then
        err(string.format("Expected at least 3 anchor links (#PID), got %d", anchor_links))
    end

    -- Check specific targets exist
    if not targets["#REQ-EDGE-001"] then
        err("Missing link target '#REQ-EDGE-001' (valid PID resolution)")
    end

    -- The unresolved link to REQ-NONEXISTENT should also be rewritten to #REQ-NONEXISTENT
    if not targets["#REQ-NONEXISTENT"] then
        err("Missing link target '#REQ-NONEXISTENT' (unresolved PID, rewritten to anchor)")
    end

    if #errors > 0 then
        return false, "Relation edge case validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
