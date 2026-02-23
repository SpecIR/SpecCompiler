-- Test oracle for VC-FLOAT-006: Caption Structure and Numbering
-- Verifies caption divs are structured correctly for filter processing:
-- - Raw caption text only (no prefix/{seq}/separator in content)
-- - Attributes include prefix, separator, seq-name, float-type

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

    -- Find all speccompiler-caption divs
    local caption_divs = {}
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-caption" then
                    table.insert(caption_divs, block)
                end
            end
        end
    end

    -- Should have at least 3 caption divs (2 figures + 1 plantuml)
    if #caption_divs < 3 then
        err(string.format("Expected at least 3 speccompiler-caption divs, got %d", #caption_divs))
        if #errors > 0 then
            return false, "Caption structure validation failed:\n  - " .. table.concat(errors, "\n  - ")
        end
        return true, nil
    end

    -- Check each caption div
    for i, div in ipairs(caption_divs) do
        local caption_id = string.format("caption[%d]", i)

        -- 1. Must have prefix attribute
        local prefix = get_attr(div, "prefix")
        if not prefix or prefix == "" then
            err(string.format("%s: missing 'prefix' attribute", caption_id))
        end

        -- 2. Must have separator attribute
        local separator = get_attr(div, "separator")
        if not separator or separator == "" then
            err(string.format("%s: missing 'separator' attribute", caption_id))
        end

        -- 3. Must have seq-name attribute
        local seq_name = get_attr(div, "seq-name")
        if not seq_name or seq_name == "" then
            err(string.format("%s: missing 'seq-name' attribute", caption_id))
        end

        -- 4. Must have float-type attribute
        local float_type = get_attr(div, "float-type")
        if not float_type or float_type == "" then
            err(string.format("%s: missing 'float-type' attribute", caption_id))
        end

        -- 5. Content must NOT contain {seq} placeholder
        local content_text = pandoc.utils.stringify(div.content)
        if content_text:find("{seq}") then
            err(string.format("%s: content contains '{seq}' placeholder (should be raw caption only): %s",
                caption_id, content_text))
        end

        -- 6. Content should NOT start with prefix (should be raw caption only)
        if prefix and content_text:match("^" .. prefix .. " ") then
            err(string.format("%s: content starts with prefix '%s' (should be raw caption only): %s",
                caption_id, prefix, content_text))
        end
    end

    if #errors > 0 then
        return false, "Caption structure validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
