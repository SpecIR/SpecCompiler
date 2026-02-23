return function(actual_doc, _)
    if not actual_doc or not actual_doc.blocks or #actual_doc.blocks == 0 then
        return false, "Expected non-empty rendered document"
    end

    local text = pandoc.utils.stringify(actual_doc)
    if not text:find("Preset Chain Probe", 1, true) then
        return false, "Rendered output missing expected title"
    end

    local caption_div = nil
    actual_doc:walk({
        Div = function(div)
            local classes = (div.attr and div.attr.classes) or div.classes or {}
            for _, c in ipairs(classes) do
                if c == "speccompiler-caption" then
                    local attrs = (div.attr and div.attr.attributes) or div.attributes or {}
                    if attrs["float-type"] == "FIGURE" then
                        caption_div = div
                    end
                end
            end
            return nil
        end
    })

    if not caption_div then
        return false, "Missing FIGURE caption div (speccompiler-caption)"
    end

    local attrs = (caption_div.attr and caption_div.attr.attributes) or caption_div.attributes or {}
    if attrs.prefix ~= "BaseFigure" then
        return false, "Expected merged preset prefix from base: BaseFigure"
    end
    if attrs.separator ~= ":::" then
        return false, "Expected merged preset separator from extension: :::"
    end

    return true
end
