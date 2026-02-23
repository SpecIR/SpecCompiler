-- Test oracle for VC-VIEW-002: View Registration
-- Verifies view registration and materialization of TOC, LOF, LOT, and sigla_list

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Collect BulletList elements and look for sigla_list empty marker
    local bullet_lists = {}
    local has_no_abbrev_marker = false

    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "BulletList" then
                table.insert(bullet_lists, block)
            elseif block.t == "Para" then
                -- Check for "[No abbreviations defined]" text (sigla_list empty case)
                local text = pandoc.utils.stringify(block)
                if text:find("%[No abbreviations defined%]") then
                    has_no_abbrev_marker = true
                end
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    -- 1. At least 3 BulletLists (TOC + LOF + LOT)
    if #bullet_lists < 3 then
        err(string.format(
            "Expected at least 3 BulletLists (TOC, LOF, LOT), got %d",
            #bullet_lists))
    end

    -- 2. At least one BulletList has content (views actually materialized)
    local has_content = false
    for _, bl in ipairs(bullet_lists) do
        if bl.content and #bl.content > 0 then
            has_content = true
            break
        end
    end
    if not has_content and #bullet_lists > 0 then
        err("BulletList views should have at least one item")
    end

    -- 3. sigla_list empty-case marker exists
    if not has_no_abbrev_marker then
        err("Expected Para with '[No abbreviations defined]' for empty sigla_list view")
    end

    if #errors > 0 then
        return false, "View registration validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
