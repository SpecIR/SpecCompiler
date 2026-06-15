-- Test oracle for VC-TYPE-001: Software Function Type
-- Verifies SF objects are created with correct attributes and structural BELONGS relations

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

    actual_doc:walk({
        Header = function(header)
            local id = header.identifier or ""
            if id:match("^SF%-") then
                sf_count = sf_count + 1
            elseif id:match("^HLR%-") then
                hlr_count = hlr_count + 1
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

    -- 3. Verify BELONGS relations in the SpecIR database
    --    Structural relations are inferred from header nesting, not explicit links.
    local sqlite3 = require("lsqlite3")
    local db = sqlite3.open(helpers.db_file, sqlite3.OPEN_READONLY)
    if not db then
        err("Could not open test database: " .. tostring(helpers.db_file))
    else
        -- Count BELONGS relations
        local belongs_count = 0
        local belongs = {}
        for row in db:nrows([[
            SELECT so_src.pid AS source_pid, so_tgt.pid AS target_pid
            FROM spec_relations r
            JOIN spec_objects so_src ON r.source_object_id = so_src.id
            JOIN spec_objects so_tgt ON r.target_object_id = so_tgt.id
            WHERE r.type_ref = 'BELONGS'
        ]]) do
            belongs_count = belongs_count + 1
            table.insert(belongs, row.source_pid .. " -> " .. row.target_pid)
        end

        if belongs_count ~= 3 then
            err(string.format("Expected 3 BELONGS relations in IR, got %d: %s",
                belongs_count, table.concat(belongs, ", ")))
        end

        -- Verify specific mappings
        local expected_mappings = {
            ["HLR-AUTH-001"] = "SF-AUTH",
            ["HLR-AUTH-002"] = "SF-AUTH",
            ["HLR-DATA-001"] = "SF-DATA",
        }
        for _, rel in ipairs(belongs) do
            local src, tgt = rel:match("(.+) %-> (.+)")
            if src and expected_mappings[src] then
                if expected_mappings[src] ~= tgt then
                    err(string.format("BELONGS: %s should point to %s, got %s",
                        src, expected_mappings[src], tgt))
                end
                expected_mappings[src] = nil  -- mark as verified
            end
        end
        for src, tgt in pairs(expected_mappings) do
            err(string.format("Missing BELONGS relation: %s -> %s", src, tgt))
        end

        db:close()
    end

    if #errors > 0 then
        return false, "SF type validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
