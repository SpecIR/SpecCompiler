-- Test oracle for VC-SYNTAX-003: blockquote disambiguation.
--
-- A blockquote is an OBJECT attribute iff its first line matches `key: value`
-- AND the key is a DECLARED attribute of the enclosing object's type (own or
-- inherited). Everything else -- prose openers like "Note:"/"TODO:",
-- undeclared keys, quotes without the pattern, bolded openers -- stays a
-- plain blockquote in the output. Spec-level metadata (version, under the H1)
-- remains permissive.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local cards, quotes = {}, {}
    actual_doc:walk{
        Div = function(d)
            if d.attr.classes:includes("spec-object-attributes") then
                table.insert(cards, pandoc.utils.stringify(d.content))
            end
        end,
        BlockQuote = function(b)
            table.insert(quotes, pandoc.utils.stringify(b.content))
        end,
    }

    -- Exactly one card: the declared `description`
    if #cards ~= 1 then
        err(string.format("expected exactly 1 attribute card, got %d", #cards))
    else
        if not cards[1]:find("DESCRIPTION:", 1, true)
            or not cards[1]:find("A declared attribute on SECTION.", 1, true) then
            err("card must render the declared description, got: " .. cards[1])
        end
    end

    -- All five prose quotes survive verbatim as blockquotes
    local expected_quotes = {
        "Note: prose remark that must stay a quote.",
        "TODO: also prose, not an attribute.",
        "status: undeclared on SECTION, so this stays prose.",
        "This quote has no key pattern at all.",
        "Warning: bolded quotes stay prose.",
    }
    if #quotes ~= #expected_quotes then
        err(string.format("expected %d surviving blockquotes, got %d: %s",
            #expected_quotes, #quotes, table.concat(quotes, " // ")))
    end
    local all_quotes = table.concat(quotes, "\n")
    for _, q in ipairs(expected_quotes) do
        if not all_quotes:find(q, 1, true) then
            err("missing surviving prose quote: " .. q)
        end
    end

    -- None of the prose openers leaked into attribute cards
    local all_cards = table.concat(cards, "\n")
    for _, label in ipairs({ "NOTE:", "TODO:", "STATUS:", "WARNING:" }) do
        if all_cards:find(label, 1, true) then
            err("prose opener leaked into an attribute card: " .. label)
        end
    end

    -- Spec-level metadata stays permissive
    local version = actual_doc.meta.version and pandoc.utils.stringify(actual_doc.meta.version)
    if version ~= "1.0" then
        err("spec-level version must remain permissive, got " .. tostring(version))
    end

    if #errors > 0 then
        return false, "blockquote disambiguation:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
