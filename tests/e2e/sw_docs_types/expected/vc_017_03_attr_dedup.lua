-- Test oracle for VC-TYPE-003: Attribute Deduplication
-- Verifies that each traceable object has exactly ONE spec-object-attributes Div
-- Regression test for duplicate attribute rendering bug in TRANSFORM phase

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SRS-DEDUP" then
        err("Spec title ID should be 'SRS-DEDUP', got: " .. tostring(title_block.identifier))
    end

    -- 2. Count spec-object-attributes Divs per object.
    -- Objects can be nested in wrapper Divs, so flatten blocks recursively.
    local current_object_id = nil
    local object_attr_counts = {}  -- object ID -> spec-object-attributes Div count

    -- Helper to check if a Div has the spec-object-attributes class
    local function has_spec_object_attrs_class(div)
        if div.t ~= "Div" then return false end
        local classes = div.classes or (div.attr and div.attr.classes) or {}
        -- Handle both userdata and table formats
        if type(classes) == "userdata" then
            -- Pandoc List - iterate directly
            for _, c in ipairs(classes) do
                if c == "spec-object-attributes" then
                    return true
                end
            end
        else
            for _, c in ipairs(classes) do
                if c == "spec-object-attributes" then
                    return true
                end
            end
        end
        return false
    end

    local function flatten_blocks(blocks, out)
        for _, block in ipairs(blocks or {}) do
            table.insert(out, block)
            if block.t == "Div" or block.t == "BlockQuote" then
                flatten_blocks(block.content or {}, out)
            end
        end
    end

    local flattened = {}
    flatten_blocks(actual_doc.blocks, flattened)

    for _, block in ipairs(flattened) do
        if block.t == "Header" then
            -- New object starts
            current_object_id = block.identifier
            if current_object_id and not object_attr_counts[current_object_id] then
                object_attr_counts[current_object_id] = 0
            end
        elseif current_object_id and has_spec_object_attrs_class(block) then
            -- Found a spec-object-attributes Div
            object_attr_counts[current_object_id] = (object_attr_counts[current_object_id] or 0) + 1
        end
    end

    -- 3. Verify each object has exactly ONE spec-object-attributes Div
    local expected_objects = {
        "TERM-TEST-001",
        "TERM-TEST-002",
        "HLR-TEST-001"
    }

    for _, obj_id in ipairs(expected_objects) do
        local count = object_attr_counts[obj_id]
        if not count then
            err(string.format("Object '%s' not found in document", obj_id))
        elseif count ~= 1 then
            err(string.format(
                "Object '%s' has %d spec-object-attributes Divs, expected exactly 1 (DEDUPLICATION BUG)",
                obj_id, count
            ))
        end
    end

    -- 4. Global check: total spec-object-attributes Divs should equal object count
    local total_attr_divs = 0
    for _, count in pairs(object_attr_counts) do
        total_attr_divs = total_attr_divs + count
    end

    -- Should have 3 objects with attributes, so 3 spec-object-attributes Divs.
    if total_attr_divs ~= 3 then
        err(string.format(
            "Total spec-object-attributes Divs: expected 3, got %d",
            total_attr_divs
        ))
    end

    if #errors > 0 then
        return false, "Attribute deduplication validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
