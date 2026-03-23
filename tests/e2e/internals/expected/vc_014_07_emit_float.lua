-- Test oracle for VC-INT-007: Emit Float Pipeline
-- Verifies: float CodeBlock replacement, bookmark markers,
-- caption Divs with full attributes, and handler dispatch.

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
    -- Collect elements of interest
    -- ========================================================================
    local caption_divs = {}
    local bookmark_starts = {}
    local bookmark_ends = {}
    local code_blocks = {}

    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                if has_class(block, "speccompiler-caption") then
                    table.insert(caption_divs, block)
                end
                walk(block.content)
            elseif block.t == "RawBlock" then
                local text = block.text or ""
                if text:match("^bookmark%-start:") then
                    table.insert(bookmark_starts, text)
                elseif text:match("^bookmark%-end:") then
                    table.insert(bookmark_ends, text)
                end
            elseif block.t == "CodeBlock" then
                table.insert(code_blocks, block)
            end
        end
    end
    walk(actual_doc.blocks)

    -- ========================================================================
    -- 1. Caption Divs: expect 3 (fig, csv table, listing — all captioned)
    -- ========================================================================
    if #caption_divs < 3 then
        err(string.format("Expected at least 3 caption Divs, got %d", #caption_divs))
    end

    -- Verify caption attributes are populated
    for i, div in ipairs(caption_divs) do
        local seq = get_attr(div, "seq-name")
        local ftype = get_attr(div, "float-type")
        local prefix = get_attr(div, "prefix")

        if not seq or seq == "" then
            err(string.format("Caption #%d missing seq-name", i))
        end
        if not ftype or ftype == "" then
            err(string.format("Caption #%d missing float-type", i))
        end
        if not prefix or prefix == "" then
            err(string.format("Caption #%d missing prefix", i))
        end
    end

    -- ========================================================================
    -- 2. Bookmark markers: one pair per captioned float
    -- ========================================================================
    if #bookmark_starts < 3 then
        err(string.format("Expected at least 3 bookmark-start markers, got %d", #bookmark_starts))
    end
    if #bookmark_ends < 3 then
        err(string.format("Expected at least 3 bookmark-end markers, got %d", #bookmark_ends))
    end

    -- ========================================================================
    -- 3. Plain code block preserved (not a float, should stay as CodeBlock)
    -- ========================================================================
    local found_plain_code = false
    for _, cb in ipairs(code_blocks) do
        local text = cb.text or ""
        if text:find("hello", 1, true) then
            found_plain_code = true
        end
    end
    if not found_plain_code then
        err("Plain 'lua' code block was incorrectly consumed as a float")
    end

    -- ========================================================================
    -- Result
    -- ========================================================================
    if #errors > 0 then
        return false, "Emit float validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
