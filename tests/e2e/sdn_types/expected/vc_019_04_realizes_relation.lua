-- Test oracle for VC-REL-004: REALIZES Relation
-- Verifies FD objects link to SF via traceability attribute (REALIZES relation)

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SDD-REAL" then
        err("Spec title ID should be 'SDD-REAL', got: " .. tostring(title_block.identifier))
    end

    -- 2. Count SF and FD objects recursively (headers may be nested)
    local sf_count = 0
    local fd_count = 0
    local realizes_links = 0

    actual_doc:walk({
        Header = function(header)
            local id = header.identifier or ""
            if id:match("^SF%-") then
                sf_count = sf_count + 1
            elseif id:match("^FD%-") then
                fd_count = fd_count + 1
            end
        end,
        Link = function(link)
            local target = link.target or ""
            -- Check if link targets an SF (REALIZES relation)
            if target:match("SF%-") then
                realizes_links = realizes_links + 1
            end
        end
    })

    -- Should have 1 SF object
    if sf_count ~= 1 then
        err(string.format("Expected 1 SF header, got %d", sf_count))
    end

    -- Should have 3 FD objects
    if fd_count ~= 3 then
        err(string.format("Expected 3 FD headers, got %d", fd_count))
    end

    -- 3. Verify REALIZES relations (one per FD)
    if realizes_links < 3 then
        err(string.format("Expected at least 3 REALIZES links to SF, got %d", realizes_links))
    end

    if #errors > 0 then
        return false, "REALIZES relation validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
