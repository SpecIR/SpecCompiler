-- Test oracle for VC-INT-004: Float Base Behavior
-- Verifies caption attributes, source attribution, and counter group assignment.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local function get_attr(el, name)
        if el.attributes then
            for _, attr in ipairs(el.attributes) do
                if attr[1] == name then return attr[2] end
            end
        end
        return nil
    end

    -- Find all speccompiler-caption Divs recursively
    local caption_divs = {}
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                for _, cls in ipairs(block.classes or {}) do
                    if cls == "speccompiler-caption" then
                        table.insert(caption_divs, block)
                        break
                    end
                end
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if #caption_divs < 3 then
        err(string.format("Expected at least 3 speccompiler-caption divs, got %d", #caption_divs))
        return false, "Float base validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Group by seq-name
    local by_seq = {}
    for _, div in ipairs(caption_divs) do
        local seq = get_attr(div, "seq-name") or "UNKNOWN"
        by_seq[seq] = by_seq[seq] or {}
        table.insert(by_seq[seq], div)
    end

    -- Verify FIGURE group
    if not by_seq["FIGURE"] or #by_seq["FIGURE"] < 1 then
        err("No FIGURE counter group caption found")
    else
        local fig = by_seq["FIGURE"][1]
        if not get_attr(fig, "prefix") then err("FIGURE caption missing prefix") end
        if not get_attr(fig, "separator") then err("FIGURE caption missing separator") end
        if get_attr(fig, "float-type") ~= "FIGURE" then
            err("FIGURE float-type: expected 'FIGURE', got '" .. tostring(get_attr(fig, "float-type")) .. "'")
        end
        if get_attr(fig, "float-number") ~= "1" then
            err("FIGURE float-number: expected '1', got '" .. tostring(get_attr(fig, "float-number")) .. "'")
        end
    end

    -- Verify TABLE group
    if not by_seq["TABLE"] or #by_seq["TABLE"] < 1 then
        err("No TABLE counter group caption found")
    else
        local tab = by_seq["TABLE"][1]
        if get_attr(tab, "float-type") ~= "TABLE" then
            err("TABLE float-type: expected 'TABLE', got '" .. tostring(get_attr(tab, "float-type")) .. "'")
        end
    end

    -- Verify LISTING group
    if not by_seq["LISTING"] or #by_seq["LISTING"] < 1 then
        err("No LISTING counter group caption found")
    else
        local lst = by_seq["LISTING"][1]
        if get_attr(lst, "float-type") ~= "LISTING" then
            err("LISTING float-type: expected 'LISTING', got '" .. tostring(get_attr(lst, "float-type")) .. "'")
        end
    end

    -- Check for source block (Div with custom-style containing source text)
    local found_source = false
    local function walk_source(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                local style = get_attr(block, "custom-style")
                if style then
                    local text = pandoc.utils.stringify(block)
                    if text:find("Engineering", 1, true) then
                        found_source = true
                    end
                end
                walk_source(block.content)
            end
        end
    end
    walk_source(actual_doc.blocks)

    if not found_source then
        err("No source attribution block found with 'Engineering' text")
    end

    if #errors > 0 then
        return false, "Float base validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
