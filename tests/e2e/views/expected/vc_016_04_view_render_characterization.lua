-- Characterization oracle for VC-VIEW (step 12 front-load): locks the CURRENT
-- end-to-end view rendering so the inline/materialize host flips cannot silently
-- change it. Covers: inline sigla first-use expansion, TOC materialization (with
-- section entries), LOF materialization (with a figure), and a populated
-- sigla_list.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local full = pandoc.utils.stringify(actual_doc)

    -- 1. Inline sigla first-use expands to the full form with the acronym.
    if not full:find("Application Programming Interface (API)", 1, true) then
        err("inline sigla first-use should expand to 'Application Programming Interface (API)'")
    end

    -- TOC and LOF both materialize into BulletLists.
    local bullet_lists = {}
    local function walk(blocks)
        for _, b in ipairs(blocks or {}) do
            if b.t == "BulletList" then
                bullet_lists[#bullet_lists + 1] = b
            elseif b.t == "Div" then
                walk(b.content)
            end
        end
    end
    walk(actual_doc.blocks)
    if #bullet_lists < 2 then
        err("expected >=2 BulletLists (TOC + LOF), got " .. #bullet_lists)
    end

    -- 2. TOC lists the sections, PID-prefixed (this form is unique to the TOC
    --    entries, distinguishing them from the plain section headers).
    for _, entry in ipairs({ "SEC-INTRO: section: Introduction", "SEC-ABBR: section: Abbreviations" }) do
        if not full:find(entry, 1, true) then
            err("TOC should contain entry '" .. entry .. "'")
        end
    end

    -- 3. LOF lists the figure with its caption number.
    if not full:find("Figure 1 - System Diagram", 1, true) then
        err("LOF should list 'Figure 1 - System Diagram'")
    end

    -- 4. sigla_list materializes the abbreviation expansion. The expansion text
    --    therefore appears at least twice (inline first-use + the list).
    local _, count = full:gsub("Application Programming Interface", "")
    if count < 2 then
        err("sigla_list should list the abbreviation (expected 'Application Programming "
            .. "Interface' >=2x, got " .. count .. ")")
    end

    if #errors > 0 then
        return false, "View render characterization failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
