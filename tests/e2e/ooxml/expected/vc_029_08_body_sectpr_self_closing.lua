-- Test oracle for VC-OOXML-008: Body sectPr replacement targets the body element
--
-- Pandoc's default reference.docx ends the body with either a populated
-- <w:sectPr>...</w:sectPr> (3.6+) or a self-closing <w:sectPr/> (3.1.x, the
-- stock Ubuntu 24.04 package). replace_body_sectpr must hit the body-level
-- element in both shapes.
--
-- Regression: the self-closing form was invisible to the scanner, so the last
-- *visible* match was the paragraph-level section break a postprocessor had
-- just injected. Replacing that break discarded its page numbering (ABNT
-- pre-textual lowerRoman) and left the body sectPr empty, so Word/LibreOffice
-- fell back to Letter page setup.

local PRETEXTUAL_SECTPR = table.concat({
    "<w:sectPr>",
    '<w:headerReference w:type="default" r:id="rId7"/>',
    '<w:pgSz w:w="11906" w:h="16838"/>',
    '<w:pgNumType w:fmt="lowerRoman" w:start="1"/>',
    "<w:titlePg/>",
    "</w:sectPr>",
})

---Document body carrying a paragraph-level section break followed by the
---body-level sectPr rendered in `body_sectpr` form.
local function document_with(body_sectpr)
    return table.concat({
        "<w:document><w:body>",
        "<w:p><w:pPr>", PRETEXTUAL_SECTPR, "</w:pPr></w:p>",
        '<w:p><w:r><w:t>Textual content</w:t></w:r></w:p>',
        body_sectpr,
        "</w:body></w:document>",
    })
end

local NEW_SECTPR = table.concat({
    "<w:sectPr>",
    '<w:pgSz w:w="11906" w:h="16838"/>',
    '<w:pgNumType w:fmt="decimal"/>',
    "</w:sectPr>",
})

return function(_, _)
    local section_manager = require("infra.format.docx.section_manager")

    local errors = {}
    local function err(msg) table.insert(errors, msg) end

    ---Every shape a Pandoc reference.docx has been observed to produce.
    local body_forms = {
        { label = "self-closing (pandoc 3.1.x)", xml = "<w:sectPr/>" },
        { label = "self-closing with space", xml = "<w:sectPr />" },
        { label = "populated (pandoc 3.6+)", xml = '<w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr>' },
    }

    for _, form in ipairs(body_forms) do
        local content = document_with(form.xml)
        local result, replaced = section_manager.replace_body_sectpr(content, NEW_SECTPR)

        if not replaced then
            err(string.format("%s: expected replaced=true, got false", form.label))
        end

        -- The injected pre-textual section break must survive untouched.
        if not result:find(PRETEXTUAL_SECTPR, 1, true) then
            err(string.format(
                "%s: paragraph-level section break was overwritten (lowerRoman page numbering lost)",
                form.label))
        end

        -- The body sectPr must now be the replacement.
        if not result:find(NEW_SECTPR, 1, true) then
            err(string.format("%s: replacement sectPr is not present in the result", form.label))
        end

        -- No empty body sectPr may survive: it makes Word/LibreOffice fall
        -- back to default (Letter) page setup.
        if result:find("<w:sectPr%s*/>") then
            err(string.format("%s: an empty <w:sectPr/> survived in the body", form.label))
        end

        -- Exactly two sections must remain: the pre-textual break + the body.
        local count = select(2, result:gsub("<w:sectPr[>/%s]", ""))
        if count ~= 2 then
            err(string.format("%s: expected 2 sectPr elements, got %d", form.label, count))
        end
    end

    -- A document whose body sectPr is absent entirely must not have its
    -- paragraph-level break cannibalised; the caller appends one instead.
    local no_body = table.concat({
        "<w:document><w:body>",
        "<w:p><w:pPr>", PRETEXTUAL_SECTPR, "</w:pPr></w:p>",
        "<w:p><w:r><w:t>Textual content</w:t></w:r></w:p>",
        "</w:body></w:document>",
    })
    local result, replaced = section_manager.replace_body_sectpr(no_body, NEW_SECTPR)
    if replaced then
        err("missing body sectPr: expected replaced=false so the caller appends one")
    end
    if not result:find(PRETEXTUAL_SECTPR, 1, true) then
        err("missing body sectPr: paragraph-level section break was overwritten")
    end

    if #errors > 0 then
        return false, "Body sectPr replacement failed:\n  - " .. table.concat(errors, "\n  - ")
    end

    return true
end
