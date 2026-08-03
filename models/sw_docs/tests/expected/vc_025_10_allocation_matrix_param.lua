-- Test oracle for VC-025 (TP 10): Allocation Matrix status param
-- Verifies `allocation_matrix: status=complete` filters the matrix to
-- complete allocation chains only (params delivered through the promoted
-- inline view, honored by the view's generate step).

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Find the allocation matrix Table
    local matrix = nil
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Table" then
                matrix = matrix or block
            elseif block.t == "Div" then
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if not matrix then
        err("Expected a Table (rendered allocation_matrix view)")
    else
        local text = pandoc.utils.stringify(matrix)
        if not text:find("HLR-ALLOC-001", 1, true) then
            err("Matrix should contain the complete chain (HLR-ALLOC-001)")
        end
        if not text:find("Complete", 1, true) then
            err("Matrix should show 'Complete' status for the full chain")
        end
        if text:find("HLR-ALLOC-002", 1, true) then
            err("Matrix contains HLR-ALLOC-002 (incomplete chain) despite status=complete -- param ignored")
        end
    end

    if #errors > 0 then
        return false, "Allocation matrix param validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
