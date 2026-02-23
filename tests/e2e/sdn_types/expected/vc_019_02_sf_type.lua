-- Test oracle for VC-TYPE-001: Software Function Type
-- Verifies SF objects are created with correct attributes and BELONGS relations

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SRS-SF" then
        err("Spec title ID should be 'SRS-SF', got: " .. tostring(title_block.identifier))
    end

    -- 2. Count object headers recursively (objects may be nested in Div wrappers)
    local sf_count = 0
    local hlr_count = 0
    local belongs_links = 0

    actual_doc:walk({
        Header = function(header)
            local id = header.identifier or ""
            if id:match("^SF%-") then
                sf_count = sf_count + 1
            elseif id:match("^HLR%-") then
                hlr_count = hlr_count + 1
            end
        end,
        Link = function(link)
            local target = link.target or ""
            if target:match("SF%-") then
                belongs_links = belongs_links + 1
            end
        end
    })

    -- Should have 2 SF objects
    if sf_count ~= 2 then
        err(string.format("Expected 2 SF headers, got %d", sf_count))
    end

    -- Should have 3 HLR objects
    if hlr_count ~= 3 then
        err(string.format("Expected 3 HLR headers, got %d", hlr_count))
    end

    -- 3. Verify BELONGS relations exist (one per HLR)
    if belongs_links < 3 then
        err(string.format("Expected at least 3 BELONGS links to SF, got %d", belongs_links))
    end

    if #errors > 0 then
        return false, "SF type validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
