-- Test oracle for VC-REL-006: XREF_DECOMPOSITION relation.
-- Verifies CSC/CSU cross-references resolve through PID_REF semantics.

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

    local function rel(target_text)
        return query_one(string.format([[
            SELECT r.type_ref, r.target_object_id, r.link_selector, o.type_ref AS target_type
            FROM spec_relations r
            JOIN spec_objects so ON so.id = r.source_object_id
            LEFT JOIN spec_objects o ON o.id = r.target_object_id
            WHERE so.pid = 'FD-AUTH-001' AND r.target_text = '%s'
        ]], target_text))
    end

    local csc_ref = rel("CSC-CORE-001")
    if not csc_ref then
        err("Missing relation FD-AUTH-001 -> CSC-CORE-001")
    else
        if csc_ref.type_ref ~= "XREF_DECOMPOSITION" then
            err("Expected XREF_DECOMPOSITION for CSC target, got " .. tostring(csc_ref.type_ref))
        end
        if csc_ref.link_selector ~= "@" then
            err("Expected @ selector for CSC target, got " .. tostring(csc_ref.link_selector))
        end
        if csc_ref.target_type ~= "CSC" then
            err("CSC target resolved to unexpected type " .. tostring(csc_ref.target_type))
        end
    end

    local csu_ref = rel("CSU-AUTH-001")
    if not csu_ref then
        err("Missing relation FD-AUTH-001 -> CSU-AUTH-001")
    else
        if csu_ref.type_ref ~= "XREF_DECOMPOSITION" then
            err("Expected XREF_DECOMPOSITION for CSU target, got " .. tostring(csu_ref.type_ref))
        end
        if csu_ref.link_selector ~= "@" then
            err("Expected @ selector for CSU target, got " .. tostring(csu_ref.link_selector))
        end
        if csu_ref.target_type ~= "CSU" then
            err("CSU target resolved to unexpected type " .. tostring(csu_ref.target_type))
        end
    end

    db:close()

    if #errors > 0 then
        return false, "Decomposition cross-reference validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
