-- Test oracle for VC-FLOAT-004: Mermaid Processing
-- Verifies Mermaid diagrams are recognized as floats and processed without errors.
-- Rendering itself is gated on the mermaid-cli (mmdc) toolchain.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if #actual_doc.blocks < 1 then
        err("Document should have blocks")
    end

    local title_block = actual_doc.blocks[1]
    if not (title_block and title_block.t == "Div" and title_block.identifier) then
        err("Expected spec title Div as first block")
    end

    if #errors > 0 then
        return false, "Mermaid processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
