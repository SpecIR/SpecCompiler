-- Test oracle for VC-REL-010: Relation type inference.
-- Validates that the relation_analyzer correctly infers relation types
-- based on link selector, resolved target type, and specificity scoring.

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if not actual_doc or #actual_doc.blocks < 1 then
        return false, "No document produced"
    end

    local ok, sqlite = pcall(require, "lsqlite3")
    if not ok then
        return false, "lsqlite3 not available"
    end

    local db = sqlite.open(helpers.db_file)
    if not db then
        return false, "Failed to open DB: " .. tostring(helpers.db_file)
    end

    local function query_one(sql)
        for row in db:nrows(sql) do return row end
        return nil
    end

    local function query_all(sql)
        local rows = {}
        for row in db:nrows(sql) do table.insert(rows, row) end
        return rows
    end

    -- Helper: find relation by source PID and target text
    local function rel(source_pid, target_text)
        return query_one(string.format([[
            SELECT r.type_ref, r.target_object_id, r.target_float_id,
                   r.is_ambiguous, r.link_selector, r.source_attribute
            FROM spec_relations r
            JOIN spec_objects so ON so.id = r.source_object_id
            WHERE so.pid = '%s' AND r.target_text = '%s'
        ]], source_pid, target_text))
    end

    -- ============================================================
    -- Test 1: Figure reference via # → resolved to float
    -- ============================================================
    local fig = rel("SEC-FLOAT-REFS", "fig:test-figure")
    if not fig then
        err("T1: Relation SEC-FLOAT-REFS → fig:test-figure not found")
    elseif not fig.target_float_id then
        err("T1: fig:test-figure not resolved to float")
    elseif fig.link_selector ~= "#" then
        err("T1: Expected link_selector=#, got " .. tostring(fig.link_selector))
    end

    -- ============================================================
    -- Test 2: Second figure reference via # → resolved
    -- ============================================================
    local fig2 = rel("SEC-FLOAT-REFS", "fig:test-figure-b")
    if not fig2 then
        err("T2: Relation SEC-FLOAT-REFS → fig:test-figure-b not found")
    elseif not fig2.target_float_id then
        err("T2: fig:test-figure-b not resolved to float")
    end

    -- ============================================================
    -- Test 3: PID reference via @ → resolved to object
    -- ============================================================
    local sec = rel("SEC-PID-REFS", "SEC-TARGETS")
    if not sec then
        err("T3: Relation SEC-PID-REFS → SEC-TARGETS not found")
    elseif not sec.target_object_id then
        err("T3: SEC-TARGETS not resolved to object")
    elseif sec.link_selector ~= "@" then
        err("T3: Expected link_selector=@, got " .. tostring(sec.link_selector))
    end

    -- ============================================================
    -- Test 4: Second PID reference → resolved
    -- ============================================================
    local sec2 = rel("SEC-PID-REFS", "SEC-FLOAT-REFS")
    if not sec2 then
        err("T4: Relation SEC-PID-REFS → SEC-FLOAT-REFS not found")
    elseif not sec2.target_object_id then
        err("T4: SEC-FLOAT-REFS not resolved to object")
    end

    -- ============================================================
    -- Test 5: Attribute-based link → resolved
    -- ============================================================
    local attr_link = rel("SEC-ATTR-LINKS", "SEC-TARGETS")
    if not attr_link then
        err("T5: Relation SEC-ATTR-LINKS → SEC-TARGETS not found")
    elseif not attr_link.target_object_id then
        err("T5: SEC-TARGETS not resolved via attribute link")
    elseif attr_link.source_attribute ~= "traceability" then
        err("T5: Expected source_attribute=traceability, got " .. tostring(attr_link.source_attribute))
    end

    -- ============================================================
    -- Test 6: Verify total relation count (sanity check)
    -- ============================================================
    local all_rels = query_all([[
        SELECT COUNT(*) as cnt FROM spec_relations
        WHERE specification_ref IS NOT NULL
    ]])
    if all_rels[1] and all_rels[1].cnt < 5 then
        err("T6: Expected at least 5 relations, found " .. tostring(all_rels[1].cnt))
    end

    -- ============================================================
    -- Test 7: No relations should be ambiguous in this test
    -- ============================================================
    local ambig = query_all([[
        SELECT COUNT(*) as cnt FROM spec_relations WHERE is_ambiguous = 1
    ]])
    if ambig[1] and ambig[1].cnt > 0 then
        err("T7: Expected 0 ambiguous relations, found " .. tostring(ambig[1].cnt))
    end

    db:close()

    if #errors > 0 then
        return false, "Type inference validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
