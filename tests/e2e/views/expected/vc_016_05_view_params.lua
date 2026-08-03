-- Test oracle for VC-016 (TP 05): View Parameters
-- Verifies key=value params survive the standalone-Code block promotion:
--   `toc: depth=1` must produce a depth-limited TOC (data-depth="1",
--   level-2 sections listed, level-3 headings excluded).

return function(actual_doc, helpers)
    helpers.strip_tracking_spans(actual_doc)
    helpers.options.ignore_data_pos = true

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    -- Find the speccompiler-toc Div produced by the promoted `toc: depth=1`
    local toc_div = nil
    local function walk(blocks)
        for _, block in ipairs(blocks or {}) do
            if block.t == "Div" then
                for _, cls in ipairs(block.classes or {}) do
                    if cls == "speccompiler-toc" then
                        toc_div = toc_div or block
                    end
                end
                walk(block.content)
            end
        end
    end
    walk(actual_doc.blocks)

    if not toc_div then
        err("Expected a speccompiler-toc Div (promoted `toc: depth=1` view)")
    else
        local depth_attr = toc_div.attributes and toc_div.attributes["data-depth"]
        if depth_attr ~= "1" then
            err(string.format(
                "TOC Div data-depth: expected '1' (from `toc: depth=1`), got '%s' -- params lost in block promotion",
                tostring(depth_attr)))
        end

        local text = pandoc.utils.stringify(toc_div)
        if not text:find("Section One", 1, true)
            or not text:find("Section Two", 1, true) then
            err("TOC should list the level-2 sections (Section One / Section Two)")
        end
        if text:find("Deep Subsection Alpha", 1, true) then
            err("TOC lists 'Deep Subsection Alpha' (level 3) despite depth=1 -- params lost")
        end
    end

    if #errors > 0 then
        return false, "View param validation failed:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
