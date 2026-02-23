-- Test oracle for VC-REL-007: Section Cross-References
-- Verifies that xref_sec (@ PID) and xref_secp (# label) resolve correctly
-- for auto-generated section PIDs and labels.
--
-- Test cases:
-- TC-01: [SPEC-SECXREF-sec1](@) → Introduction (@ PID, XREF_SEC inferred)
-- TC-02: [SPEC-SECXREF-sec1.1](@) → Background (@ PID, XREF_SEC inferred)
-- TC-03: [section:introduction](#) → Introduction (# label, XREF_SECP inferred)
-- TC-04: [section:design-overview](#) → Design Overview (# label, XREF_SECP inferred)
-- TC-05: type_ref = 'XREF_SEC' for @ section links
-- TC-06: type_ref = 'XREF_SECP' for # section links
-- TC-07: Total relation count = 4

return function(actual_doc, helpers)
    if not actual_doc or #actual_doc.blocks < 1 then
        return false, "Pipeline produced no output"
    end

    local sqlite = require("lsqlite3")
    if not helpers.db_file then
        return false, "helpers.db_file not provided by runner"
    end

    local db = sqlite.open(helpers.db_file)
    if not db then
        return false, "Failed to open pipeline DB: " .. helpers.db_file
    end

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local function query(sql)
        local rows = {}
        for row in db:nrows(sql) do
            table.insert(rows, row)
        end
        return rows
    end

    -- Query all relations with source and target context
    local relations = query([[
        SELECT r.id, r.target_text, r.is_ambiguous,
               r.target_object_id, r.target_float_id,
               r.link_selector, r.type_ref,
               so.pid AS source_pid,
               tobj.pid AS target_pid,
               tobj.title_text AS target_title
        FROM spec_relations r
        LEFT JOIN spec_objects so ON r.source_object_id = so.id
        LEFT JOIN spec_objects tobj ON r.target_object_id = tobj.id
        ORDER BY r.id
    ]])

    -- TC-01: [SPEC-SECXREF-sec1](@) → Introduction
    local tc01 = false
    for _, r in ipairs(relations) do
        if r.link_selector == "@" and r.target_text == "SPEC-SECXREF-sec1" then
            tc01 = true
            if not r.target_object_id then
                err("TC-01: SPEC-SECXREF-sec1 not resolved")
            elseif r.target_pid ~= "SPEC-SECXREF-sec1" then
                err("TC-01: expected target PID SPEC-SECXREF-sec1, got " ..
                    tostring(r.target_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-01: should NOT be ambiguous")
            end
        end
    end
    if not tc01 then err("TC-01: relation not found") end

    -- TC-02: [SPEC-SECXREF-sec1.1](@) → Background
    local tc02 = false
    for _, r in ipairs(relations) do
        if r.link_selector == "@" and r.target_text == "SPEC-SECXREF-sec1.1" then
            tc02 = true
            if not r.target_object_id then
                err("TC-02: SPEC-SECXREF-sec1.1 not resolved")
            elseif r.target_pid ~= "SPEC-SECXREF-sec1.1" then
                err("TC-02: expected target PID SPEC-SECXREF-sec1.1, got " ..
                    tostring(r.target_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-02: should NOT be ambiguous")
            end
        end
    end
    if not tc02 then err("TC-02: relation not found") end

    -- TC-03: [section:introduction](#) → Introduction
    local tc03 = false
    for _, r in ipairs(relations) do
        if r.link_selector == "#" and r.target_text == "section:introduction" then
            tc03 = true
            if not r.target_object_id then
                err("TC-03: section:introduction not resolved")
            elseif r.target_pid ~= "SPEC-SECXREF-sec1" then
                err("TC-03: expected target PID SPEC-SECXREF-sec1, got " ..
                    tostring(r.target_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-03: should NOT be ambiguous")
            end
        end
    end
    if not tc03 then err("TC-03: relation not found") end

    -- TC-04: [section:design-overview](#) → Design Overview
    local tc04 = false
    for _, r in ipairs(relations) do
        if r.link_selector == "#" and r.target_text == "section:design-overview" then
            tc04 = true
            if not r.target_object_id then
                err("TC-04: section:design-overview not resolved")
            elseif r.target_pid ~= "SPEC-SECXREF-sec2" then
                err("TC-04: expected target PID SPEC-SECXREF-sec2, got " ..
                    tostring(r.target_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-04: should NOT be ambiguous")
            end
        end
    end
    if not tc04 then err("TC-04: relation not found") end

    -- TC-05: Verify type_ref = 'XREF_SEC' for @ section links
    local xref_sec_count = 0
    for _, r in ipairs(relations) do
        if r.link_selector == "@" and r.target_object_id then
            if r.type_ref == "XREF_SEC" then
                xref_sec_count = xref_sec_count + 1
            else
                err("TC-05: @ section link has type_ref=" ..
                    tostring(r.type_ref) .. " (expected XREF_SEC)")
            end
        end
    end
    if xref_sec_count ~= 2 then
        err("TC-05: expected 2 XREF_SEC relations, found " .. xref_sec_count)
    end

    -- TC-06: Verify type_ref = 'XREF_SECP' for # section links
    local xref_secp_count = 0
    for _, r in ipairs(relations) do
        if r.link_selector == "#" and r.target_object_id then
            if r.type_ref == "XREF_SECP" then
                xref_secp_count = xref_secp_count + 1
            else
                err("TC-06: # section link has type_ref=" ..
                    tostring(r.type_ref) .. " (expected XREF_SECP)")
            end
        end
    end
    if xref_secp_count ~= 2 then
        err("TC-06: expected 2 XREF_SECP relations, found " .. xref_secp_count)
    end

    -- TC-07: Total relation count = 4
    if #relations ~= 4 then
        err(string.format("TC-07: expected 4 relations, found %d", #relations))
    end

    db:close()

    if #errors > 0 then
        return false, "Section xref tests failed (" .. #errors ..
            " errors):\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
