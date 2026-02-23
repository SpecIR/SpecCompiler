-- Test oracle for VC-VIEW-001: Inline Views
-- Verifies inline view syntax is processed correctly:
--   TOC materializes as a BulletList with heading entries
--   LOF/LOT produce empty-case Para markers (no figures/tables in input)

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if #actual_doc.blocks < 3 then
        err(string.format("Expected at least 3 blocks, got %d", #actual_doc.blocks))
        return false, "Inline view validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- 1. TOC view: find BulletList elements (materialized views)
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
        err("Expected at least 1 BulletList (materialized TOC view), got 0")
    end

    local has_content = false
    for _, bl in ipairs(bullet_lists) do
        if bl.content and #bl.content > 0 then
            has_content = true
            break
        end
    end

    if not has_content then
        err("BulletList (TOC) should have at least one item")
    end

    -- 2. LOF/LOT empty-case markers: Para containing "[No figures found]" or "[No tables found]"
    local empty_markers = 0
    local function walk_for_markers(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Para" then
                local text = pandoc.utils.stringify(block)
                if text:find("%[No figures found%]") or text:find("%[No tables found%]") then
                    empty_markers = empty_markers + 1
                end
            elseif block.t == "Div" then
                walk_for_markers(block.content)
            end
        end
    end
    walk_for_markers(actual_doc.blocks)

    if empty_markers < 1 then
        err(string.format(
            "Expected at least 1 empty-case marker ([No figures found] or [No tables found]), got %d",
            empty_markers))
    end

    if #errors > 0 then
        return false, "Inline view validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
