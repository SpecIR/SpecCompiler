-- Test oracle for VC-OUT-005: Spec Object Render Handler
-- Exercises load_type_handler, filter chain, on_render_SpecObject dispatch,
-- and composite heading ID patching.

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    local function has_class(el, cls_name)
        for _, cls in ipairs(el.classes or {}) do
            if cls == cls_name then return true end
        end
        return false
    end

    -- ========================================================================
    -- Collect cover semantic Divs and Headers
    -- ========================================================================
    local cover_divs = {}
    local headers = {}
    local raw_blocks = {}

    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                -- Check for cover-* classes
                for _, cls in ipairs(block.classes or {}) do
                    if cls:match("^cover%-") then
                        cover_divs[cls] = pandoc.utils.stringify(block)
                        break
                    end
                end
                walk(block.content)
            elseif block.t == "Header" then
                table.insert(headers, block)
            elseif block.t == "RawBlock" then
                table.insert(raw_blocks, block)
            end
        end
    end
    walk(actual_doc.blocks)

    -- ========================================================================
    -- 1. Cover type handler was invoked: semantic Divs exist
    -- ========================================================================
    if not cover_divs["cover-title"] then
        err("Missing cover-title Div (type handler not invoked?)")
    elseif not cover_divs["cover-title"]:find("Test Report Title", 1, true) then
        err("cover-title text mismatch: " .. cover_divs["cover-title"])
    end

    if not cover_divs["cover-subtitle"] then
        err("Missing cover-subtitle Div")
    end

    if not cover_divs["cover-author"] then
        err("Missing cover-author Div")
    elseif not cover_divs["cover-author"]:find("Jane Smith", 1, true) then
        err("cover-author text mismatch: " .. cover_divs["cover-author"])
    end

    if not cover_divs["cover-date"] then
        err("Missing cover-date Div")
    end

    if not cover_divs["cover-docid"] then
        err("Missing cover-docid Div")
    elseif not cover_divs["cover-docid"]:find("DOC%-TEST%-001") then
        err("cover-docid text mismatch: " .. cover_divs["cover-docid"])
    end

    if not cover_divs["cover-version"] then
        err("Missing cover-version Div")
    end

    -- ========================================================================
    -- 2. Cover section markers exist (RawBlocks)
    -- ========================================================================
    local found_cover_start = false
    local found_cover_end = false
    for _, raw in ipairs(raw_blocks) do
        if raw.text and raw.text:find("cover%-section%-start") then
            found_cover_start = true
        end
        if raw.text and raw.text:find("cover%-section%-end") then
            found_cover_end = true
        end
    end
    if not found_cover_start then
        err("Missing cover-section-start RawBlock")
    end
    if not found_cover_end then
        err("Missing cover-section-end RawBlock")
    end

    -- ========================================================================
    -- 3. EXEC_SUMMARY exists as composite (heading ID patching path)
    --    Composite types don't go through full type-handler rendering.
    --    Instead, their heading IDs get patched to match their PID.
    -- ========================================================================
    local found_exec_header = false
    for _, h in ipairs(headers) do
        local text = pandoc.utils.stringify(h)
        if text:find("Executive Summary", 1, true) or text:find("EXECSUM", 1, true) then
            found_exec_header = true
        end
    end
    if not found_exec_header then
        err("Missing EXEC_SUMMARY header")
    end

    -- ========================================================================
    -- 4. Section headers exist (composite heading ID patching)
    -- ========================================================================
    if #headers < 2 then
        err("Expected at least 2 headers (exec_summary + section), got " .. #headers)
    end

    -- ========================================================================
    -- Result
    -- ========================================================================
    if #errors > 0 then
        return false, "Render handler validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
