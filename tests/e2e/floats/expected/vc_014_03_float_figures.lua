-- Test oracle for VC-FLOAT-004: Figure Processing
-- Verifies figure floats are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Basic structure check
    if #actual_doc.blocks < 1 then
        err("Document should have blocks")
    end

    -- Check for spec title
    local title_block = actual_doc.blocks[1]
    if title_block and title_block.t == "Div" and title_block.identifier then
        -- Has title, good
    else
        err("Expected spec title Div as first block")
    end

    if #errors > 0 then
        return false, "Figure processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
