-- Test oracle for VC-INT-006: Float Utilities
-- Exercises float_base decoration, positioning, image sizing, and source attribution paths.

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

    local function has_class(el, cls_name)
        for _, cls in ipairs(el.classes or {}) do
            if cls == cls_name then return true end
        end
        return false
    end

    -- ========================================================================
    -- Collect caption Divs and source Divs
    -- ========================================================================
    local caption_divs = {}
    local source_divs = {}

    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                if has_class(block, "speccompiler-caption") then
                    table.insert(caption_divs, block)
                end
                local style = get_attr(block, "custom-style")
                if style == "Source" then
                    table.insert(source_divs, block)
                end
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    -- ========================================================================
    -- 1. Caption Divs: expect at least 4 (fig-sourced, tab-after, fig-top, fig-landscape)
    --    code-nocap has no caption; math may or may not depending on handler
    -- ========================================================================
    if #caption_divs < 4 then
        err(string.format("Expected at least 4 speccompiler-caption divs, got %d", #caption_divs))
    end

    -- Group by float-type
    local by_type = {}
    for _, div in ipairs(caption_divs) do
        local ft = get_attr(div, "float-type") or "UNKNOWN"
        by_type[ft] = by_type[ft] or {}
        table.insert(by_type[ft], div)
    end

    -- ========================================================================
    -- 2. FIGURE captions: at least 3 (fig-sourced, fig-top, fig-landscape)
    -- ========================================================================
    if not by_type["FIGURE"] or #by_type["FIGURE"] < 3 then
        err(string.format("Expected at least 3 FIGURE captions, got %d",
            by_type["FIGURE"] and #by_type["FIGURE"] or 0))
    else
        -- Check seq-name on first FIGURE caption
        local fig1 = by_type["FIGURE"][1]
        if get_attr(fig1, "seq-name") ~= "FIGURE" then
            err("FIGURE seq-name: expected 'FIGURE', got '" ..
                tostring(get_attr(fig1, "seq-name")) .. "'")
        end
    end

    -- ========================================================================
    -- 3. TABLE caption: at least 1 (tab-after)
    -- ========================================================================
    if not by_type["TABLE"] or #by_type["TABLE"] < 1 then
        err("No TABLE caption found (expected from tab-after)")
    else
        local tab1 = by_type["TABLE"][1]
        if get_attr(tab1, "seq-name") ~= "TABLE" then
            err("TABLE seq-name: expected 'TABLE', got '" ..
                tostring(get_attr(tab1, "seq-name")) .. "'")
        end
    end

    -- ========================================================================
    -- 4. Source attribution: must find "Engineering Team" in a Source-styled Div
    -- ========================================================================
    local found_source = false
    for _, div in ipairs(source_divs) do
        local text = pandoc.utils.stringify(div)
        if text:find("Engineering Team", 1, true) then
            found_source = true
            break
        end
    end
    if not found_source then
        err("No source attribution Div with 'Engineering Team' text found")
    end

    -- ========================================================================
    -- 5. No LISTING caption expected (code-nocap has no caption attribute)
    -- ========================================================================
    if by_type["LISTING"] and #by_type["LISTING"] > 0 then
        err(string.format("Expected 0 LISTING captions (code-nocap has none), got %d",
            #by_type["LISTING"]))
    end

    -- ========================================================================
    -- Result
    -- ========================================================================
    if #errors > 0 then
        return false, "Float utilities validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
