-- Test oracle for VC-INT-026: Attribute Paragraph Parsing
-- The fixture's keys (simple_key, multi_word, numeric_key) are NOT declared
-- for the enclosing type (SECTION), so under the declared-names rule these
-- blockquotes are PROSE: preserved in the output, never extracted, never
-- rendered as attribute cards.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local blockquotes, cards = {}, 0
    actual_doc:walk{
        BlockQuote = function(b)
            table.insert(blockquotes, pandoc.utils.stringify(b.content))
        end,
        Div = function(d)
            if d.attr.classes:includes("spec-object-attributes") then
                cards = cards + 1
            end
        end,
    }

    -- All three undeclared-key blockquotes survive as prose
    if #blockquotes ~= 3 then
        err(string.format("Expected 3 surviving prose blockquotes, got %d", #blockquotes))
    end
    local all = table.concat(blockquotes, "\n")
    for _, needle in ipairs({
        "simple_key: Simple string value",
        "multi_word: A longer value with multiple words",
        "numeric_key: 42",
    }) do
        if not all:find(needle, 1, true) then
            err("Missing surviving prose blockquote: " .. needle)
        end
    end

    -- No attribute card is rendered for undeclared keys
    if cards ~= 0 then
        err(string.format("Expected 0 attribute cards, got %d", cards))
    end

    if #errors > 0 then
        return false, "Attribute parsing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
