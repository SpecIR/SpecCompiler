-- Test oracle for VC-INT-018: View Utilities
-- Verifies views are rendered and floats processed in output.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if #actual_doc.blocks < 3 then
        err(string.format("Expected at least 3 blocks, got %d", #actual_doc.blocks))
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
        err("Expected at least 1 BulletList (materialized view)")
    end

    -- Check that at least one BulletList has content
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

    -- Check caption Div exists (float was processed)
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
        err("No float caption found (float should be rendered for LOF)")
    end

    if #errors > 0 then
        return false, "View utilities validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
