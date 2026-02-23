-- Test oracle for VC-INT-010: Render Decoration
-- Verifies bookmark markers, caption Divs, and header structure in output.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Check for bookmark markers (RawBlock with speccompiler format)
    local bookmark_count = 0
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "RawBlock" and block.format == "speccompiler" then
                if block.text and block.text:find("bookmark%-start:") then
                    bookmark_count = bookmark_count + 1
                end
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if bookmark_count < 1 then
        err(string.format("Expected at least 1 bookmark-start marker, got %d", bookmark_count))
    end

    -- Check for caption Div
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
        err("No speccompiler-caption Div found for float")
    end

    -- Check headers exist
    local header_count = 0
    local function walk_headers(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Header" then
                header_count = header_count + 1
            elseif block.t == "Div" then
                walk_headers(block.content)
            end
        end
    end
    walk_headers(actual_doc.blocks)

    if header_count < 2 then
        err(string.format("Expected at least 2 headers, got %d", header_count))
    end

    if #errors > 0 then
        return false, "Render decoration validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
