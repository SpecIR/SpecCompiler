return function(actual_doc, _)
    if not actual_doc or not actual_doc.blocks then
        return false, "Expected rendered document"
    end

    local text = pandoc.utils.stringify(actual_doc)
    if not text:find("No HLR-VC traceability relations found.", 1, true) then
        return false, "Expected empty traceability fallback message from text block syntax"
    end

    return true
end
