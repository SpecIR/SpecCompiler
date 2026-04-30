-- Test oracle for VC-REL-007: XREF_DIC relation.
-- Verifies dictionary references remain part of the sw_docs model.

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
            WHERE so.pid = 'HLR-DIC-001' AND r.target_text = '%s'
        ]], target_text))
    end

    local auth_ref = rel("DIC-AUTH-001")
    if not auth_ref then
        err("Missing relation HLR-DIC-001 -> DIC-AUTH-001")
    else
        if auth_ref.type_ref ~= "XREF_DIC" then
            err("Expected XREF_DIC for DIC-AUTH-001, got " .. tostring(auth_ref.type_ref))
        end
        if auth_ref.link_selector ~= "@" then
            err("Expected @ selector for DIC-AUTH-001, got " .. tostring(auth_ref.link_selector))
        end
        if auth_ref.target_type ~= "DIC" then
            err("DIC-AUTH-001 resolved to unexpected target type " .. tostring(auth_ref.target_type))
        end
    end

    local token_ref = rel("DIC-TOKEN-001")
    if not token_ref then
        err("Missing relation HLR-DIC-001 -> DIC-TOKEN-001")
    elseif token_ref.type_ref ~= "XREF_DIC" then
        err("Expected XREF_DIC for DIC-TOKEN-001, got " .. tostring(token_ref.type_ref))
    end

    db:close()

    if #errors > 0 then
        return false, "Dictionary cross-reference validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
