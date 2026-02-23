-- Test oracle for VC-ASSEMBLY-001: Assembly Order
-- Verifies document assembly preserves file_seq order, not alphabetical

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SPEC-ASSEMBLY-001" then
        err("Spec title ID should be 'SPEC-ASSEMBLY-001'")
    end

    -- 2. Find headers and verify order
    -- Expected: Introduction (from main), Included Section (from _aaa_included), Conclusion (from main)
    local headers = {}
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Header" then
            table.insert(headers, pandoc.utils.stringify(block.content))
        end
    end

    -- The key test: "Introduction" must come BEFORE any included content
    -- and "Conclusion" must come LAST
    local intro_idx = nil
    local conclusion_idx = nil

    for i, header in ipairs(headers) do
        if header:match("Introduction") then
            intro_idx = i
        elseif header:match("Conclusion") then
            conclusion_idx = i
        end
    end

    if intro_idx and conclusion_idx then
        if intro_idx >= conclusion_idx then
            err("Introduction should appear before Conclusion")
        end
    end

    if #errors > 0 then
        return false, "Assembly order validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
