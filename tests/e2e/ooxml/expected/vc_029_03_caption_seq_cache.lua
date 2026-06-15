-- Test oracle for VC-OOXML-CACHE: Caption SEQ Cached Value
-- Renders the DOCX and asserts that the cached placeholder shown for each
-- SEQ field (the value Word/LibreOffice display until F9) matches the
-- float's compiled number within its counter_group. Regression guard for
-- the "Figure 1 / Figure 1" bug where every cached placeholder was "1".

return function(actual_doc, helpers)
    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    if not actual_doc or #actual_doc.blocks < 1 then
        err("Document AST should have blocks")
        return false, table.concat(errors, "\n")
    end

    local build_dir = helpers.build_dir .. "/"
    local suite_dir = helpers.suite_dir .. "/"
    local test_name = "vc_029_03_caption_seq_cache"
    local docx_path = build_dir .. test_name .. ".docx"
    local docx_db = build_dir .. "docx_seq_" .. tostring(os.clock()):gsub("%.", "") .. ".db"

    local engine = require("core.engine")
    local project_info = {
        project = { code = "TEST_OOXML_SEQ", name = "Caption SEQ cache" },
        template = "default",
        files = { suite_dir .. test_name .. ".md" },
        output_dir = build_dir,
        output_format = "docx",
        outputs = {{ format = "docx", path = docx_path }},
        db_file = docx_db,
        logging = { level = "WARN" },
    }

    local gen_ok, gen_err = pcall(engine.run_project, project_info)
    if not gen_ok then
        err("DOCX generation failed: " .. tostring(gen_err))
        return false, table.concat(errors, "\n")
    end

    local docx_helpers = require("docx_helpers")
    local xml = docx_helpers.get_document_xml(docx_path)
    if not xml then
        err("Could not read word/document.xml from " .. docx_path)
        return false, table.concat(errors, "\n")
    end

    -- Each caption paragraph emits:
    --   "Figure " + <SEQ FIGURE \* ARABIC> + " - <text>"
    -- After the field's "separate" marker the cached value lives in a
    -- single <w:t>...</w:t>; capture that placeholder plus the SEQ
    -- group name and the caption text so we can assert per counter group.
    local pattern = "SEQ%s+(%w+)%s+\\%*%s+ARABIC%s*</w:instrText></w:r>" ..
                    "<w:r>[^<]*<w:fldChar w:fldCharType=\"separate\"/></w:r>" ..
                    "<w:r>[^<]*<w:t[^>]*>([^<]+)</w:t></w:r>" ..
                    "<w:r>[^<]*<w:fldChar w:fldCharType=\"end\"/></w:r>" ..
                    "<w:r>[^<]*<w:t[^>]*>%s*[%-–:]%s*([^<]+)</w:t>"

    local hits = {}
    for seq_name, cached, caption_text in xml:gmatch(pattern) do
        table.insert(hits, {
            seq_name = seq_name,
            cached = cached,
            caption = caption_text,
        })
    end

    if #hits < 5 then
        err(string.format("Expected at least 5 SEQ-field captions in document.xml, got %d", #hits))
        return false, "Caption SEQ cache validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    -- Group hits by counter_group (= SEQ field name) preserving document order.
    local groups, group_order = {}, {}
    for _, hit in ipairs(hits) do
        local g = hit.seq_name
        if not groups[g] then
            groups[g] = {}
            table.insert(group_order, g)
        end
        table.insert(groups[g], hit)
    end

    -- Within each group, cached placeholders must read 1, 2, 3 ... in order.
    for _, g in ipairs(group_order) do
        for i, hit in ipairs(groups[g]) do
            if hit.cached ~= tostring(i) then
                err(string.format(
                    "%s caption #%d: expected cached SEQ value '%d', got '%s' (caption: %q)",
                    g, i, i, tostring(hit.cached), hit.caption))
            end
        end
    end

    -- Sanity: FIGURE group has at least 3 entries, TABLE at least 2.
    if not groups["FIGURE"] or #groups["FIGURE"] < 3 then
        err(string.format("Expected FIGURE group with >=3 captions, got %d",
            groups["FIGURE"] and #groups["FIGURE"] or 0))
    end
    if not groups["TABLE"] or #groups["TABLE"] < 2 then
        err(string.format("Expected TABLE group with >=2 captions, got %d",
            groups["TABLE"] and #groups["TABLE"] or 0))
    end

    if #errors > 0 then
        return false, "Caption SEQ cache validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
