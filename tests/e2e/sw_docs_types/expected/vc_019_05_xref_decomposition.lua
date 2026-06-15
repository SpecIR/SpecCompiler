-- Test oracle for VC-REL-006: software decomposition cross-references in sw_docs.
--
-- XREF_DECOMPOSITION is a LABEL_REF (# selector). Therefore:
--   * a @-PID link to a CSC/CSU resolves as the GENERIC section cross-reference
--     XREF_SEC (CSC/CSU extend TRACEABLE -> SECTION); and
--   * a #-label link resolves to the type-specific XREF_DECOMPOSITION.
-- The distance-aware scorer keeps the #-label case unambiguous: the exact
-- CSC/CSU target (distance 0) beats XREF_SECP's SECTION (distance > 0).

return function(actual_doc, helpers)
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

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local function rel(target_text)
        for row in db:nrows(string.format([[
            SELECT r.type_ref, r.target_object_id, r.link_selector, r.is_ambiguous,
                   o.type_ref AS target_type
            FROM spec_relations r
            JOIN spec_objects so ON so.id = r.source_object_id
            LEFT JOIN spec_objects o ON o.id = r.target_object_id
            WHERE so.pid = 'FD-AUTH-001' AND r.target_text = '%s'
        ]], target_text)) do
            return row
        end
        return nil
    end

    -- target_text -> { selector, expected relation type, expected target type }
    local cases = {
        { "CSC-CORE-001",     "@", "XREF_SEC",           "CSC" },
        { "CSU-AUTH-001",     "@", "XREF_SEC",           "CSU" },
        { "csc:core-services","#", "XREF_DECOMPOSITION", "CSC" },
        { "csu:auth-service", "#", "XREF_DECOMPOSITION", "CSU" },
    }

    for _, case in ipairs(cases) do
        local target, selector, want_type, want_target = case[1], case[2], case[3], case[4]
        local r = rel(target)
        if not r then
            err("Missing relation FD-AUTH-001 -> " .. target)
        else
            if not r.target_object_id then
                err(target .. " did not resolve")
            end
            if r.link_selector ~= selector then
                err(string.format("%s: expected selector %s, got %s", target, selector, tostring(r.link_selector)))
            end
            if r.type_ref ~= want_type then
                err(string.format("%s: expected %s, got %s", target, want_type, tostring(r.type_ref)))
            end
            if r.target_type ~= want_target then
                err(string.format("%s: resolved to unexpected target type %s", target, tostring(r.target_type)))
            end
            if r.is_ambiguous ~= 0 then
                err(target .. " should NOT be ambiguous")
            end
        end
    end

    db:close()

    if #errors > 0 then
        return false, "Decomposition cross-reference validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
