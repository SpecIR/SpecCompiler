-- Test oracle for VC-INT-027: one attribute per blockquote.
--
-- CommonSpec disambiguation rule: one blockquote declares ONE attribute.
-- Adjacent `> ` lines (SoftBreak continuation) and `>`-separated paragraphs
-- inside the same blockquote all continue the FIRST attribute's value, even
-- when a continuation line looks like `key: value`. Distinct attributes
-- require separate blank-line-separated blockquotes.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local cards = {}
    actual_doc:walk{
        Div = function(d)
            if d.attr.classes:includes("spec-object-attributes") then
                table.insert(cards, pandoc.utils.stringify(d.content))
            end
        end,
    }

    local card_text = table.concat(cards, "\n")

    -- The adjacent-line blockquote is ONE description attribute whose value
    -- carries the continuation line verbatim
    if not card_text:find("DESCRIPTION:", 1, true) then
        err("missing DESCRIPTION attribute card")
    end
    if not card_text:find("term: stays inside the description value", 1, true) then
        err("continuation line must stay inside the description value")
    end
    if card_text:find("TERM:", 1, true) then
        err("continuation line was promoted to its own TERM attribute")
    end

    -- The multi-paragraph blockquote is ONE attribute with block continuation
    if not card_text:find("para two continues the same attribute", 1, true) then
        err("second paragraph must continue the same attribute's value")
    end

    if #errors > 0 then
        return false, "one attribute per blockquote:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
