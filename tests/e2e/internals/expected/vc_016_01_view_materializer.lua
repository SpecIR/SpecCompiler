-- Test oracle for VC-INT-005: View Materialization
-- Verifies TOC and LOF views are materialized as BulletLists in the output.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if #actual_doc.blocks < 3 then
        err(string.format("Expected at least 3 blocks, got %d", #actual_doc.blocks))
        return false, "View materialization validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Find BulletList elements (materialized views)
    local bullet_lists = {}
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "BulletList" then
                table.insert(bullet_lists, block)
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if #bullet_lists < 1 then
        err("Expected at least 1 BulletList (materialized view), got 0")
    end

    -- Check at least one BulletList has non-empty content
    local has_content = false
    for _, bl in ipairs(bullet_lists) do
        if bl.content and #bl.content > 0 then
            has_content = true
            break
        end
    end

    if not has_content then
        err("BulletList views should have at least one item")
    end

    if #errors > 0 then
        return false, "View materialization validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
