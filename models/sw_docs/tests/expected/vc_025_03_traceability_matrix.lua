return function(actual_doc, _)
    if not actual_doc or not actual_doc.blocks then
        return false, "Expected rendered document"
    end

    local tables = 0
    actual_doc:walk({
        Table = function()
            tables = tables + 1
        end
    })
    if tables < 1 then
        return false, "Expected at least one Table block from traceability_matrix view"
    end

    local text = pandoc.utils.stringify(actual_doc)
    local must_have = {
        "HLR ID",
        "VC ID",
        "Result",
        "HLR-001",
        "VC-001",
        "VC-002",
        "Pass",
        "Fail",
        "Blocked",
        "Not Run",
    }

    for _, token in ipairs(must_have) do
        if not text:find(token, 1, true) then
            return false, "Missing token in rendered traceability matrix output: " .. token
        end
    end

    return true
end
