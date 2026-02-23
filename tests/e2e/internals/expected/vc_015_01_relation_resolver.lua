-- Test oracle for VC-INT-006: Relation Resolution
-- Verifies PID (@) and header (#) traceability links are resolved to anchors.

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

    -- Should have at least 2 traceability links
    if #links < 2 then
        err(string.format("Expected at least 2 traceability links, got %d", #links))
    end

    -- Check resolved links: targets should start with # (resolved to anchors)
    local resolved_count = 0
    for _, link in ipairs(links) do
        local target = link.target or ""
        if target:sub(1, 1) == "#" and #target > 1 then
            resolved_count = resolved_count + 1
        end
    end

    if resolved_count < 2 then
        err(string.format("Expected at least 2 resolved links (target=#...), got %d", resolved_count))
    end

    if #errors > 0 then
        return false, "Relation resolution validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
