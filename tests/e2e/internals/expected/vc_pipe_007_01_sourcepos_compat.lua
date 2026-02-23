-- Test oracle for VC-INT-024: Sourcepos Cleanup
-- Verifies tracking spans are stripped from emitted output.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- After stripping, no Span should have data-pos attribute
    local tracking_spans = 0
    local function walk_inlines(inlines)
        for _, inl in ipairs(inlines or {}) do
            if inl.t == "Span" then
                if inl.attributes then
                    for _, attr in ipairs(inl.attributes) do
                        if attr[1] == "data-pos" then
                            tracking_spans = tracking_spans + 1
                        end
                    end
                end
                walk_inlines(inl.content)
            elseif inl.t == "Link" then
                walk_inlines(inl.content)
            elseif inl.t == "Emph" or inl.t == "Strong" then
                walk_inlines(inl.content)
            end
        end
    end

    local function walk_blocks(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Para" or block.t == "Plain" then
                walk_inlines(block.content)
            elseif block.t == "Header" then
                walk_inlines(block.content)
            elseif block.t == "Div" or block.t == "BlockQuote" then
                walk_blocks(block.content)
            elseif block.t == "BulletList" or block.t == "OrderedList" then
                for _, item in ipairs(block.content or {}) do
                    walk_blocks(item)
                end
            end
        end
    end
    walk_blocks(actual_doc.blocks)

    if tracking_spans > 0 then
        err(string.format("Found %d remaining tracking spans with data-pos after stripping", tracking_spans))
    end

    -- Verify document structure is preserved
    if #actual_doc.blocks < 3 then
        err(string.format("Expected at least 3 blocks after stripping, got %d", #actual_doc.blocks))
    end

    -- Check text content is preserved
    local doc_text = pandoc.utils.stringify(actual_doc)
    if not doc_text:find("bold") then
        err("Bold text content was lost during stripping")
    end
    if not doc_text:find("italic") then
        err("Italic text content was lost during stripping")
    end

    if #errors > 0 then
        return false, "Sourcepos cleanup validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
