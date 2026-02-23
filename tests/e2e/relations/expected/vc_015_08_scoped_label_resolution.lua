-- Test oracle for VC-REL-006: Scoped Label Resolution
-- Uses DB queries to verify that # resolution uses implicit scoping
-- (closest scope to global) with proper ambiguity detection.
--
-- Test cases:
-- TC-01: [fig:diagram](#) from ALPHA → ALPHA's float, not ambiguous
-- TC-02: [fig:diagram](#) from BETA  → BETA's float, not ambiguous
-- TC-03: [fig:unique](#) from GAMMA  → resolved, not ambiguous
-- TC-04: [ALPHA:fig:diagram](#) from GAMMA → explicit scope to ALPHA
-- TC-05: [BETA:fig:diagram](#) from GAMMA  → explicit scope to BETA
-- TC-06: [fig:diagram](#) from GAMMA → ambiguous (2 matches at spec scope)
-- TC-07: [section:alpha](#) from DELTA → ALPHA object by label
-- TC-08: Total # relation count = 7

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

    -- Query all # relations with source and target context
    local relations = query([[
        SELECT r.id, r.target_text, r.is_ambiguous,
               r.target_float_id, r.target_object_id,
               so.pid AS source_pid,
               tf.parent_object_id AS target_float_parent_id,
               tp.pid AS target_float_parent_pid,
               tobj.pid AS target_object_pid
        FROM spec_relations r
        LEFT JOIN spec_objects so ON r.source_object_id = so.id
        LEFT JOIN spec_floats tf ON r.target_float_id = tf.id
        LEFT JOIN spec_objects tp ON tf.parent_object_id = tp.id
        LEFT JOIN spec_objects tobj ON r.target_object_id = tobj.id
        WHERE r.link_selector = '#'
        ORDER BY r.id
    ]])

    -- TC-01: [fig:diagram](#) from ALPHA → ALPHA's float, not ambiguous
    local tc01 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "ALPHA" and r.target_text == "fig:diagram" then
            tc01 = true
            if not r.target_float_id then
                err("TC-01: fig:diagram from ALPHA not resolved")
            elseif r.target_float_parent_pid ~= "ALPHA" then
                err("TC-01: expected ALPHA's float, got parent=" ..
                    tostring(r.target_float_parent_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-01: should NOT be ambiguous")
            end
        end
    end
    if not tc01 then err("TC-01: relation not found") end

    -- TC-02: [fig:diagram](#) from BETA → BETA's float, not ambiguous
    local tc02 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "BETA" and r.target_text == "fig:diagram" then
            tc02 = true
            if not r.target_float_id then
                err("TC-02: fig:diagram from BETA not resolved")
            elseif r.target_float_parent_pid ~= "BETA" then
                err("TC-02: expected BETA's float, got parent=" ..
                    tostring(r.target_float_parent_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-02: should NOT be ambiguous")
            end
        end
    end
    if not tc02 then err("TC-02: relation not found") end

    -- TC-03: [fig:unique](#) from GAMMA → resolved, not ambiguous
    local tc03 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "GAMMA" and r.target_text == "fig:unique" then
            tc03 = true
            if not r.target_float_id then
                err("TC-03: fig:unique from GAMMA not resolved")
            end
            if r.is_ambiguous ~= 0 then
                err("TC-03: should NOT be ambiguous")
            end
        end
    end
    if not tc03 then err("TC-03: relation not found") end

    -- TC-04: [ALPHA:fig:diagram](#) from GAMMA → ALPHA's float
    local tc04 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "GAMMA" and r.target_text
           and r.target_text:find("ALPHA") and r.target_text:find("diagram") then
            tc04 = true
            if not r.target_float_id then
                err("TC-04: explicit scope ALPHA:fig:diagram not resolved")
            elseif r.target_float_parent_pid ~= "ALPHA" then
                err("TC-04: expected ALPHA's float, got parent=" ..
                    tostring(r.target_float_parent_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-04: should NOT be ambiguous")
            end
        end
    end
    if not tc04 then err("TC-04: relation not found") end

    -- TC-05: [BETA:fig:diagram](#) from GAMMA → BETA's float
    local tc05 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "GAMMA" and r.target_text
           and r.target_text:find("BETA") and r.target_text:find("diagram") then
            tc05 = true
            if not r.target_float_id then
                err("TC-05: explicit scope BETA:fig:diagram not resolved")
            elseif r.target_float_parent_pid ~= "BETA" then
                err("TC-05: expected BETA's float, got parent=" ..
                    tostring(r.target_float_parent_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-05: should NOT be ambiguous")
            end
        end
    end
    if not tc05 then err("TC-05: relation not found") end

    -- TC-06: [fig:diagram](#) from GAMMA → AMBIGUOUS
    local tc06 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "GAMMA" and r.target_text == "fig:diagram" then
            tc06 = true
            if not r.target_float_id then
                err("TC-06: fig:diagram from GAMMA should still resolve (first match)")
            end
            if r.is_ambiguous ~= 1 then
                err("TC-06: fig:diagram from GAMMA should be AMBIGUOUS")
            end
        end
    end
    if not tc06 then err("TC-06: relation not found") end

    -- TC-07: [section:alpha](#) from DELTA → ALPHA object
    local tc07 = false
    for _, r in ipairs(relations) do
        if r.source_pid == "DELTA" and r.target_text == "section:alpha" then
            tc07 = true
            if not r.target_object_id then
                err("TC-07: section:alpha from DELTA not resolved")
            elseif r.target_object_pid ~= "ALPHA" then
                err("TC-07: expected ALPHA object, got " ..
                    tostring(r.target_object_pid))
            end
            if r.is_ambiguous ~= 0 then
                err("TC-07: should NOT be ambiguous")
            end
        end
    end
    if not tc07 then err("TC-07: relation not found") end

    -- TC-08: Total # relation count
    if #relations ~= 7 then
        err(string.format("TC-08: expected 7 # relations, found %d", #relations))
    end

    db:close()

    if #errors > 0 then
        return false, "Scoped label resolution failed (" .. #errors ..
            " errors):\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
