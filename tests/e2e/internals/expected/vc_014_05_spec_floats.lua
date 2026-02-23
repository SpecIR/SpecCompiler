-- Test oracle for VC-INT-012: Float Type Aliases
-- Verifies fig->FIGURE, csv->TABLE, src->LISTING alias resolution in captions.

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

    -- Find all speccompiler-caption Divs
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
        return false, "Float alias validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Verify resolved types: fig->FIGURE, csv->TABLE, src->LISTING
    local expected_types = { "FIGURE", "TABLE", "LISTING" }
    local found_types = {}
    for _, div in ipairs(caption_divs) do
        local ft = get_attr(div, "float-type")
        if ft then found_types[ft] = true end
    end

    for _, t in ipairs(expected_types) do
        if not found_types[t] then
            err("Missing float-type '" .. t .. "' in caption attributes")
        end
    end

    -- Verify each caption has matching seq-name = float-type
    for _, div in ipairs(caption_divs) do
        local ft = get_attr(div, "float-type")
        local sn = get_attr(div, "seq-name")
        if ft and sn and ft ~= sn then
            err(string.format("float-type '%s' != seq-name '%s' (should match for base types)", ft, sn))
        end
    end

    if #errors > 0 then
        return false, "Float alias validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
