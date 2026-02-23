-- Test oracle for VC-INT-026: Attribute Paragraph Parsing
-- Verifies blockquote attributes are correctly parsed.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Find all BlockQuote elements
    local blockquotes = {}
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "BlockQuote" then
                table.insert(blockquotes, block)
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    -- Should have at least 3 attribute blockquotes
    if #blockquotes < 3 then
        err(string.format("Expected at least 3 BlockQuotes, got %d", #blockquotes))
    end

    -- Check each blockquote has attribute pattern (key: value)
    local attr_keys = {}
    for _, bq in ipairs(blockquotes) do
        local text = pandoc.utils.stringify(bq)
        local key = text:match("^([%w_]+):")
        if key then
            attr_keys[key] = true
        end
    end

    local expected_keys = { "simple_key", "multi_word", "numeric_key" }
    for _, key in ipairs(expected_keys) do
        if not attr_keys[key] then
            err(string.format("Missing attribute key: '%s'", key))
        end
    end

    if #errors > 0 then
        return false, "Attribute parsing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
