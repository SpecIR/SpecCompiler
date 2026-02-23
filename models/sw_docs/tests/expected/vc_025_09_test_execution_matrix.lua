return function(actual_doc, _)
    if not actual_doc or not actual_doc.blocks then
        return false, "Expected rendered document"
    end

    local table_count = 0
    actual_doc:walk({
        Table = function()
            table_count = table_count + 1
        end
    })

    if table_count < 1 then
        return false, "Expected table output from test_execution_matrix view"
    end

    local text = pandoc.utils.stringify(actual_doc)
    local must_have = {
        "VC ID",
        "HLR",
        "VC-010",
        "HLR-010",
    }

    for _, token in ipairs(must_have) do
        if not text:find(token, 1, true) then
            return false, "Missing token in rendered test_execution_matrix output: " .. token
        end
    end

    return true
end
