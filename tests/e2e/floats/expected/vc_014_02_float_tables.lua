-- Test oracle for VC-FLOAT-002: Table Processing
-- Verifies CSV, TSV, and list-table formats are processed correctly

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- 1. Verify spec title
    local title_block = actual_doc.blocks[1]
    if not title_block or title_block.t ~= "Div" then
        err("Block 1 should be spec title Div")
    elseif title_block.identifier ~= "SPEC-FLOAT-002" then
        err("Spec title ID should be 'SPEC-FLOAT-002'")
    end

    -- 2. Count tables - should have 3 (CSV, TSV, list-table) wrapped in speccompiler-table Divs
    local table_count = 0
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-table" then
                    table_count = table_count + 1
                end
            end
        end
    end

    if table_count ~= 3 then
        err(string.format("Expected 3 speccompiler-table Divs (CSV, TSV, list-table), got %d", table_count))
    end

    -- 3. Count captions - each table should have a caption
    local caption_count = 0
    for _, block in ipairs(actual_doc.blocks) do
        if block.t == "Div" and block.classes then
            for _, cls in ipairs(block.classes) do
                if cls == "speccompiler-caption" then
                    caption_count = caption_count + 1
                end
            end
        end
    end

    if caption_count < 3 then
        err(string.format("Expected at least 3 captions, got %d", caption_count))
    end

    -- 4. Links authored inside list-table cells must pass through the normal
    -- relation/citation pipeline: @ and # become resolved links, @cite becomes Cite.
    local table_internal_links = 0
    local table_cites = 0
    local raw_selector_links = {}

    local function walk(node, in_table)
        local node_type = type(node)
        if node_type ~= "table" and node_type ~= "userdata" then return end
        local now_in_table = in_table
        if node.t == "Div" and node.classes then
            for _, cls in ipairs(node.classes) do
                if cls == "speccompiler-table" then
                    now_in_table = true
                    break
                end
            end
        end

        if now_in_table and node.t == "Link" then
            local target = node.target or ""
            if target == "@" or target == "#" or target == "@cite" or target == "@citep" then
                table.insert(raw_selector_links, target)
            elseif target:match("^#") then
                table_internal_links = table_internal_links + 1
            end
        elseif now_in_table and node.t == "Cite" then
            table_cites = table_cites + 1
        end

        local traversed_named = false
        if node.content then
            for i = 1, #node.content do walk(node.content[i], now_in_table) end
            traversed_named = true
        elseif node.c then
            walk(node.c, now_in_table)
            traversed_named = true
        end
        for _, key in ipairs({ "caption", "head", "bodies", "body", "foot", "rows", "cells", "contents" }) do
            if node[key] then
                walk(node[key], now_in_table)
                traversed_named = true
            end
        end
        if traversed_named then return end
        local ok_len, len = pcall(function() return #node end)
        if ok_len then
            for i = 1, len do walk(node[i], now_in_table) end
        end
    end

    walk(actual_doc.blocks, false)

    if table_internal_links < 2 then
        err(string.format("Expected at least 2 resolved internal links inside speccompiler-table, got %d", table_internal_links))
    end
    if table_cites < 1 then
        err("Expected at least 1 Cite element inside speccompiler-table")
    end
    if #raw_selector_links > 0 then
        err("Expected no raw CommonSpec selector links inside speccompiler-table, found: " .. table.concat(raw_selector_links, ", "))
    end

    -- 5. The DB must also know those table-cell links as relations, not only
    -- the final rendered AST.
    local ok_sqlite, sqlite = pcall(require, "lsqlite3")
    if not ok_sqlite then
        err("lsqlite3 not available")
    elseif not helpers.db_file then
        err("helpers.db_file not provided")
    else
        local db = sqlite.open(helpers.db_file, sqlite.OPEN_READONLY)
        if not db then
            err("Failed to open DB: " .. tostring(helpers.db_file))
        else
            local counts = { at = 0, hash = 0, cite = 0 }
            for row in db:nrows([[
                SELECT link_selector, target_text, type_ref,
                       target_object_id IS NOT NULL AS has_object,
                       target_float_id IS NOT NULL AS has_float
                FROM spec_relations
                WHERE target_text IN ('SPEC-FLOAT-002-sec1', 'csv:csv-example', 'smith2024')
            ]]) do
                if row.link_selector == "@" and row.target_text == "SPEC-FLOAT-002-sec1" and row.has_object == 1 then
                    counts.at = counts.at + 1
                elseif row.link_selector == "#" and row.target_text == "csv:csv-example" and row.has_float == 1 then
                    counts.hash = counts.hash + 1
                elseif row.link_selector == "@cite" and row.target_text == "smith2024" and row.type_ref == "XREF_CITATION" then
                    counts.cite = counts.cite + 1
                end
            end
            db:close()

            if counts.at < 1 then err("Expected resolved @ relation from table cell") end
            if counts.hash < 1 then err("Expected resolved # relation from table cell") end
            if counts.cite < 1 then err("Expected typed @cite relation from table cell") end
        end
    end

    if #errors > 0 then
        return false, "Table processing validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
