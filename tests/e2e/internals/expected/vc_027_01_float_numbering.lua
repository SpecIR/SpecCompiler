-- Test oracle for VC-INT-017: Float Numbering Across Counter Groups
-- Verifies sequential numbering within each counter group (FIGURE, TABLE, LISTING)
-- and independence between counter groups when floats are interleaved.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Helper to get attribute from div
    local function get_attr(div, name)
        if div.attributes then
            for _, attr in ipairs(div.attributes) do
                if attr[1] == name then
                    return attr[2]
                end
            end
        end
        return nil
    end

    -- Recursively find all speccompiler-caption Divs in document order
    local caption_divs = {}
    local function walk_blocks(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                local is_caption = false
                if block.classes then
                    for _, cls in ipairs(block.classes) do
                        if cls == "speccompiler-caption" then
                            is_caption = true
                            break
                        end
                    end
                end
                if is_caption then
                    table.insert(caption_divs, block)
                end
                -- Recurse into nested content
                if block.content then
                    walk_blocks(block.content)
                end
            end
        end
    end
    walk_blocks(actual_doc.blocks)

    -- Expect 7 captions total: 4 figures + 2 tables + 1 listing
    if #caption_divs < 7 then
        err(string.format("Expected at least 7 speccompiler-caption divs, got %d", #caption_divs))
        return false, "Float numbering validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Group captions by seq-name (= counter_group)
    local groups = {}
    for _, div in ipairs(caption_divs) do
        local seq_name = get_attr(div, "seq-name") or "UNKNOWN"
        if not groups[seq_name] then
            groups[seq_name] = {}
        end
        table.insert(groups[seq_name], {
            float_number = get_attr(div, "float-number"),
            float_type = get_attr(div, "float-type"),
        })
    end

    -- Verify FIGURE counter group: 4 floats numbered 1..4
    local figures = groups["FIGURE"]
    if not figures then
        err("No FIGURE counter group found")
    else
        if #figures ~= 4 then
            err(string.format("FIGURE group: expected 4 captions, got %d", #figures))
        end
        for i, fig in ipairs(figures) do
            if fig.float_number ~= tostring(i) then
                err(string.format("FIGURE[%d]: expected float-number='%d', got '%s'",
                    i, i, fig.float_number or "nil"))
            end
        end
    end

    -- Verify TABLE counter group: 2 floats numbered 1..2
    local tables = groups["TABLE"]
    if not tables then
        err("No TABLE counter group found")
    else
        if #tables ~= 2 then
            err(string.format("TABLE group: expected 2 captions, got %d", #tables))
        end
        for i, tab in ipairs(tables) do
            if tab.float_number ~= tostring(i) then
                err(string.format("TABLE[%d]: expected float-number='%d', got '%s'",
                    i, i, tab.float_number or "nil"))
            end
        end
    end

    -- Verify LISTING counter group: 1 float numbered 1
    local listings = groups["LISTING"]
    if not listings then
        err("No LISTING counter group found")
    else
        if #listings ~= 1 then
            err(string.format("LISTING group: expected 1 caption, got %d", #listings))
        end
        if listings[1] and listings[1].float_number ~= "1" then
            err(string.format("LISTING[1]: expected float-number='1', got '%s'",
                listings[1].float_number or "nil"))
        end
    end

    if #errors > 0 then
        return false, "Float numbering validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
