---Native Pandoc Lua filter for DOCX output.
---Converts speccompiler format markers to OOXML for Word output.
---
---This filter is compatible with pandoc --lua-filter for external CLI execution.
---
---Features:
---  - Converts RawBlock("speccompiler", "page-break") to OOXML page break
---  - Converts RawBlock("speccompiler", "vertical-space:NNNN") to OOXML spacing (twips)
---  - Converts RawBlock("speccompiler", "bookmark-start:ID:NAME") to OOXML bookmark start
---  - Converts RawBlock("speccompiler", "bookmark-end:ID") to OOXML bookmark end
---  - Converts speccompiler-caption Div to OOXML caption with SEQ field
---  - Converts speccompiler-numbered-equation Div to OOXML numbered equation
---  - Converts speccompiler-toc Div to native Word TOC field
---  - Converts RawInline("speccompiler", "view:NAME:CONTENT") to OOXML inline
---
---@usage pandoc --lua-filter=docx.lua -f json -t docx input.json -o output.docx
---@module models.default.filters.docx

local xml = require("infra.format.xml")
local float_anchor = require("pipeline.shared.float_anchor")

-- ============================================================================
-- OOXML DOM Construction Helpers
-- ============================================================================

-- A4 dimensions in twips
local A4_WIDTH = 11906
local A4_HEIGHT = 16838

---Build field code run sequence (begin, instrText, separate, placeholder, end).
---@param instr string Field instruction text (e.g., " SEQ Figure \\* ARABIC ")
---@param placeholder string|nil Placeholder text (default "1")
---@return table Array of xml nodes
local function build_field_code(instr, placeholder)
    placeholder = placeholder or "1"
    return {
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "begin"})}),
        xml.node("w:r", {}, {xml.node("w:instrText", {["xml:space"] = "preserve"}, {xml.text(instr)})}),
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "separate"})}),
        xml.node("w:r", {}, {xml.node("w:t", {}, {xml.text(placeholder)})}),
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "end"})}),
    }
end

---Append all elements from an array into a target array.
---@param target table Target array
---@param source table Source array of elements to append
local function append_all(target, source)
    for _, v in ipairs(source) do
        table.insert(target, v)
    end
end

---Generate OOXML for a page break.
---@return string OOXML page break paragraph
local function ooxml_page_break()
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:br", {["w:type"] = "page"})
        })
    }))
end

---Generate OOXML for section break with orientation change.
---Used for position="p" landscape pages.
---@param orientation string "portrait" or "landscape"
---@return string OOXML section break paragraph
local function ooxml_section_break_orientation(orientation)
    local w, h
    local pgSz_attrs
    if orientation == "landscape" then
        -- Swap dimensions for landscape
        w = A4_HEIGHT
        h = A4_WIDTH
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h), ["w:orient"] = "landscape"}
    else
        w = A4_WIDTH
        h = A4_HEIGHT
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h)}
    end

    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:sectPr", {}, {
                xml.node("w:pgSz", pgSz_attrs),
                xml.node("w:type", {["w:val"] = "nextPage"}),
            })
        })
    }))
end

---Generate OOXML for vertical spacing.
---@param twips number Spacing in twips (1440 twips = 1 inch)
---@return string OOXML for spacing paragraph
local function ooxml_vertical_space(twips)
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:spacing", {["w:before"] = tostring(twips)})
        })
    }))
end

---Generate OOXML for bookmark as a zero-content paragraph.
---Pandoc's DOCX writer drops standalone bookmarkStart/End elements,
---so we wrap both in a single empty paragraph to ensure they survive.
---The bookmark is a point bookmark (start+end at same location),
---which is sufficient for PAGEREF (page number lookup) and hyperlink anchors.
---@param bm_id number Bookmark ID
---@param bm_name string Bookmark name
---@return string OOXML paragraph containing bookmark
local function ooxml_bookmark_paragraph(bm_id, bm_name)
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:spacing", {["w:before"] = "0", ["w:after"] = "0", ["w:line"] = "20", ["w:lineRule"] = "exact"}),
            xml.node("w:rPr", {}, {
                xml.node("w:sz", {["w:val"] = "2"}),
            }),
        }),
        xml.node("w:bookmarkStart", {
            ["w:id"] = tostring(bm_id),
            ["w:name"] = bm_name,
        }),
        xml.node("w:bookmarkEnd", {
            ["w:id"] = tostring(bm_id),
        }),
    }))
end

---Generate OOXML caption paragraph with SEQ field.
---@param prefix string Caption prefix (e.g., "Figure", "Table")
---@param seq_name string SEQ field name
---@param separator string Separator after number (e.g., ":", "-")
---@param caption string Caption text
---@param style string Paragraph style
---@param keep_with_next boolean|nil If true, adds keepNext to prevent orphaning
---@param number string|nil Pre-computed float number to cache as the SEQ placeholder
---@return string OOXML caption paragraph
local function ooxml_caption(prefix, seq_name, separator, caption, style, keep_with_next, number)
    local pPr_children = {
        xml.node("w:pStyle", {["w:val"] = style}),
    }
    if keep_with_next then
        table.insert(pPr_children, xml.node("w:keepNext"))
    end

    local children = {
        xml.node("w:pPr", {}, pPr_children),
        -- Prefix run (e.g., "Figure ")
        xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(prefix .. " ")}),
        }),
    }

    -- SEQ field code runs. The cached placeholder is the value Word/LibreOffice
    -- show before the user updates fields (F9), so pass float-number when known
    -- to avoid every caption showing "1" until field-update.
    local placeholder = (number and number ~= "") and number or nil
    append_all(children, build_field_code(" SEQ " .. seq_name .. " \\* ARABIC ", placeholder))

    -- Separator and caption text
    table.insert(children, xml.node("w:r", {}, {
        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(" " .. separator .. " " .. caption)}),
    }))

    return xml.serialize_element(xml.node("w:p", {}, children))
end

-- ============================================================================
-- Cover Page Semantic Div Support
-- ============================================================================

---Map of cover-page semantic CSS classes to Word paragraph style IDs.
local COVER_CLASS_MAP = {
    ["cover-title"]    = "CoverTitle",
    ["cover-subtitle"] = "CoverSubtitle",
    ["cover-author"]   = "CoverAuthor",
    ["cover-date"]     = "CoverDate",
    ["cover-docid"]    = "CoverDocId",
    ["cover-version"]  = "CoverVersion",
}

---Generate OOXML for a styled paragraph (used by cover page semantic divs).
---@param text string Paragraph text
---@param style string Word paragraph style ID
---@return string OOXML styled paragraph
local function ooxml_styled_para(text, style)
    return xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = style})
        }),
        xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(text)})
        })
    }))
end

---Generate OOXML for a semantic spec-object header paragraph.
---@param text string Header text
---@param bookmark_name string|nil Bookmark target, usually the object PID
---@return string OOXML styled paragraph
local function ooxml_spec_object_header(text, bookmark_name)
    local children = {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = "SpecObjectHeader"}),
            xml.node("w:keepNext"),
            -- Keep object headers in Word's outline/TOC without using Heading1-5.
            xml.node("w:outlineLvl", {["w:val"] = "0"}),
        }),
    }

    if bookmark_name and bookmark_name ~= "" then
        local bm_id = float_anchor.bookmark_id(bookmark_name)
        table.insert(children, xml.node("w:bookmarkStart", {
            ["w:id"] = tostring(bm_id),
            ["w:name"] = bookmark_name,
        }))
        table.insert(children, xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(text)})
        }))
        table.insert(children, xml.node("w:bookmarkEnd", {
            ["w:id"] = tostring(bm_id),
        }))
    else
        table.insert(children, xml.node("w:r", {}, {
            xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(text)})
        }))
    end

    return xml.serialize_element(xml.node("w:p", {}, children))
end

-- ============================================================================
-- Marker Parsing
-- ============================================================================

---Parse a speccompiler marker text.
---@param text string Marker text (e.g., "page-break", "vertical-space:1440")
---@return string marker_type Type of marker
---@return string|nil value Optional value for parameterized markers
local function parse_marker(text)
    local marker_type, value = text:match("^([^:]+):?(.*)$")
    if value == "" then
        value = nil
    end
    return marker_type, value
end

---Check if a Div has a specific class.
---@param div pandoc.Div The div to check
---@param class_name string Class name to look for
---@return boolean has_class True if div has the class
local function has_class(div, class_name)
    for _, c in ipairs(div.classes or {}) do
        if c == class_name then
            return true
        end
    end
    return false
end

---Get attribute value from Div.
---@param div pandoc.Div The div
---@param attr_name string Attribute name
---@return string|nil Attribute value
local function get_attr(div, attr_name)
    if div.attr and div.attr.attributes then
        return div.attr.attributes[attr_name]
    end
    return nil
end

-- ============================================================================
-- RawBlock Handler
-- ============================================================================

---Convert a speccompiler RawBlock to OOXML.
---@param block pandoc.RawBlock The block to convert
---@return pandoc.RawBlock|nil Converted OOXML block, or nil to remove
local function convert_speccompiler_block(block)
    local text = block.text

    -- Handle bookmark-start:ID:NAME
    -- Combines start+end into a single paragraph (Pandoc drops standalone bookmark elements)
    local bm_id, bm_name = text:match("^bookmark%-start:(%d+):(.+)$")
    if bm_id and bm_name then
        return pandoc.RawBlock("openxml", ooxml_bookmark_paragraph(tonumber(bm_id), bm_name))
    end

    -- Handle bookmark-end:ID (already combined with bookmark-start above)
    local end_id = text:match("^bookmark%-end:(%d+)$")
    if end_id then
        return {}  -- Remove - handled in bookmark-start
    end

    -- Parse simple markers
    local marker_type, value = parse_marker(text)

    if marker_type == "page-break" then
        return pandoc.RawBlock("openxml", ooxml_page_break())

    elseif marker_type == "vertical-space" then
        local twips = tonumber(value)
        if twips and twips > 0 then
            return pandoc.RawBlock("openxml", ooxml_vertical_space(twips))
        else
            -- Default to 1 inch (1440 twips) if no valid value
            return pandoc.RawBlock("openxml", ooxml_vertical_space(1440))
        end

    elseif marker_type == "section-break-before" then
        -- Section break with orientation for position="p"
        local orientation = value or "portrait"
        return pandoc.RawBlock("openxml", ooxml_section_break_orientation(orientation))

    elseif marker_type == "section-break-after" then
        -- Section break back to portrait after float page
        local orientation = value or "portrait"
        return pandoc.RawBlock("openxml", ooxml_section_break_orientation(orientation))

    else
        -- Unknown speccompiler marker - remove
        return {}
    end
end

---Convert a speccompiler RawInline to OOXML.
---@param inline pandoc.RawInline The inline to convert
---@return pandoc.RawInline|nil Converted OOXML inline, or nil to remove
local function convert_speccompiler_inline(inline)
    local text = inline.text

    -- Handle view:NAME:CONTENT - view content is already OOXML
    local view_name, view_content = text:match("^view:([^:]+):(.+)$")
    if view_name and view_content then
        return pandoc.RawInline("openxml", view_content)
    end

    -- Unknown inline marker - remove
    return {}
end

-- ============================================================================
-- Div Handlers
-- ============================================================================

---Convert speccompiler-caption Div to OOXML.
---@param div pandoc.Div The caption div
---@return pandoc.RawBlock OOXML caption
local function convert_caption_div(div)
    local seq_name = get_attr(div, "seq-name") or "Figure"
    local prefix = get_attr(div, "prefix") or "Figure"
    local separator = get_attr(div, "separator") or ":"
    local style = get_attr(div, "style") or "Caption"
    local number = get_attr(div, "float-number")

    -- Extract caption text from Div content
    local caption = pandoc.utils.stringify(div.content)

    -- Caption comes before content, so use keepNext to prevent orphaning
    return pandoc.RawBlock("openxml", ooxml_caption(prefix, seq_name, separator, caption, style, true, number))
end

---Convert speccompiler-numbered-equation Div to a single-paragraph OOXML layout.
---Finds the pandoc.Math element inside the Div, downcasts to InlineMath so
---Pandoc emits <m:oMath> (not <m:oMathPara>) inline, and wraps with RawInlines
---that build the custom tabstop + SEQ-field paragraph.
---@param div pandoc.Div The equation div
---@return pandoc.Para|table Mixed-content paragraph or {} to remove
local function convert_equation_div(div)
    local seq_name = get_attr(div, "seq-name") or "Equation"
    local number = get_attr(div, "number") or "1"
    local identifier = get_attr(div, "identifier") or ""

    -- Find the Math element anywhere inside div.content.
    local math_elt = nil
    pandoc.walk_block(div, {
        Math = function(m)
            math_elt = m
            return nil
        end
    })
    if not math_elt then
        return {}
    end

    -- Build bookmark OOXML (matches the old template).
    local bookmark_start_xml, bookmark_end_xml = "", ""
    if identifier and identifier ~= "" then
        local bm_id = float_anchor.bookmark_id(identifier)
        bookmark_start_xml = xml.serialize_element(xml.node("w:bookmarkStart", {
            ["w:id"] = tostring(bm_id),
            ["w:name"] = identifier,
        }))
        bookmark_end_xml = xml.serialize_element(xml.node("w:bookmarkEnd", {
            ["w:id"] = tostring(bm_id),
        }))
    end

    -- SEQ field runs — reuse the existing build_field_code helper.
    local seq_runs = {}
    append_all(seq_runs, build_field_code(
        " SEQ " .. seq_name .. " \\* ARABIC ",
        tostring(number or "1")
    ))
    local seq_xml = ""
    for _, run in ipairs(seq_runs) do
        seq_xml = seq_xml .. xml.serialize_element(run)
    end

    -- Custom pPr + first tab (before the math).
    -- KNOWN: Pandoc's docx writer emits its own <w:pPr> on the returned Para, so
    -- the final paragraph contains two <w:pPr> elements (Pandoc's, then ours).
    -- Word tolerates this and honors our tabstops; the DOCX is schema-invalid
    -- but renders correctly. The cleaner fix would be constructing the whole
    -- paragraph as a single RawBlock("openxml", ...), but that sacrifices
    -- Pandoc's native <m:oMath> emission from the Math element, which is the
    -- whole point of this refactor.
    local ppr_xml = xml.serialize_element(
        xml.node("w:pPr", {}, {
            xml.node("w:tabs", {}, {
                xml.node("w:tab", {["w:val"] = "center", ["w:pos"] = "4680"}),
                xml.node("w:tab", {["w:val"] = "right", ["w:pos"] = "9360"}),
            }),
        })
    )
    local first_tab_xml = xml.serialize_element(xml.node("w:r", {}, { xml.node("w:tab") }))

    -- Trailing: tab, bookmark-start, "(", SEQ field, ")", bookmark-end.
    local trailing = table.concat({
        xml.serialize_element(xml.node("w:r", {}, { xml.node("w:tab") })),
        bookmark_start_xml,
        xml.serialize_element(xml.node("w:r", {}, { xml.node("w:t", {}, { xml.text("(") }) })),
        seq_xml,
        xml.serialize_element(xml.node("w:r", {}, { xml.node("w:t", {}, { xml.text(")") }) })),
        bookmark_end_xml,
    })

    -- Downcast DisplayMath → InlineMath so Pandoc emits <m:oMath> without the
    -- <m:oMathPara> wrapper. <m:oMathPara> forces Pandoc to open a fresh
    -- paragraph, which would split our single-paragraph tabstop + SEQ-field
    -- layout across two paragraphs and break the centered-math + right-number
    -- visual.
    local inline_math = pandoc.Math("InlineMath", math_elt.text)

    return pandoc.Para({
        pandoc.RawInline("openxml", ppr_xml .. first_tab_xml),
        inline_math,
        pandoc.RawInline("openxml", trailing),
    })
end

---Convert speccompiler-table Div.
---For now, just unwrap the content - Pandoc handles table conversion.
---@param div pandoc.Div The table div
---@return table Content blocks
local function convert_table_div(div)
    -- Just return the content; Pandoc handles table-to-OOXML conversion
    return div.content
end

---Convert speccompiler-toc Div to native Word TOC field.
---Generates a dynamic TOC field that Word/LibreOffice renders on document open.
---@param div pandoc.Div The TOC div (from toc.lua view)
---@param heading_text string|nil Text from the preceding heading (if any)
---@return table Array of RawBlock elements
local function convert_toc_div(div, heading_text)
    local depth = get_attr(div, "data-depth") or "3"
    local instr = string.format(' TOC \\o "1-%s" ', depth)

    local result = {}

    -- If a preceding heading was captured, emit it with TOCHeading style
    -- (unnumbered: heading_numberer only processes Heading1-5)
    -- Must include explicit run properties because Word's built-in
    -- "Contents Heading" style uses blue color; we need black.
    if heading_text then
        local toc_heading = xml.serialize_element(xml.node("w:p", {}, {
            xml.node("w:pPr", {}, {
                xml.node("w:pStyle", {["w:val"] = "TOCHeading"})
            }),
            xml.node("w:r", {}, {
                xml.node("w:rPr", {}, {
                    xml.node("w:color", {["w:val"] = "000000"}),
                }),
                xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(heading_text)})
            })
        }))
        table.insert(result, pandoc.RawBlock("openxml", toc_heading))
    end

    -- TOC field start paragraph (begin + instrText + separate)
    local field_start = xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "begin"})}),
        xml.node("w:r", {}, {xml.node("w:instrText", {["xml:space"] = "preserve"}, {xml.text(instr)})}),
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "separate"})}),
    }))
    table.insert(result, pandoc.RawBlock("openxml", field_start))

    -- TOC field end paragraph
    local field_end = xml.serialize_element(xml.node("w:p", {}, {
        xml.node("w:r", {}, {xml.node("w:fldChar", {["w:fldCharType"] = "end"})}),
    }))
    table.insert(result, pandoc.RawBlock("openxml", field_end))

    -- Page break after TOC
    table.insert(result, pandoc.RawBlock("openxml", ooxml_page_break()))

    return result
end

---Find the first Header inside a block list.
---@param blocks table[] Blocks to search
---@return table|nil Header block
local function find_first_header(blocks)
    for _, block in ipairs(blocks or {}) do
        if block.t == "Header" then
            return block
        end
        if block.content then
            local found = find_first_header(block.content)
            if found then return found end
        end
    end
    return nil
end

---Convert a spec-object-header wrapper into a semantic DOCX paragraph.
---Spec objects should not reuse Word Heading1-5 styles: those belong to
---document sections. The PID bookmark is preserved for cross-references.
---@param div pandoc.Div The spec-object-header Div
---@return pandoc.RawBlock
local function convert_spec_object_header_div(div)
    local header = find_first_header(div.content)
    local text = pandoc.utils.stringify(header and header.content or div.content)
    local bookmark_name = nil
    if header then
        bookmark_name = header.identifier
            or (header.attr and header.attr.identifier)
            or (header.attr and header.attr[1])
    end
    bookmark_name = bookmark_name
        or div.identifier
        or (div.attr and div.attr.identifier)
        or (div.attr and div.attr[1])

    return pandoc.RawBlock("openxml", ooxml_spec_object_header(text, bookmark_name))
end

-- ============================================================================
-- Link Extension Replacement
-- ============================================================================

---Replace .ext placeholder with .docx in cross-document links.
---@param link pandoc.Link The link to process
---@return pandoc.Link Modified link
local function replace_ext_placeholder(link)
    if link.target then
        link.target = link.target:gsub("%.ext#", ".docx#")
        link.target = link.target:gsub("%.ext$", ".docx")
    end
    return link
end

-- ============================================================================
-- Filter Table (shared between module API and native Pandoc mode)
-- ============================================================================

---Find speccompiler-toc Div, checking both direct and wrapped cases.
---Pandoc's sourcepos extension wraps blocks in Divs with data-pos attribute,
---so the speccompiler-toc Div may be nested inside a wrapper Div.
---@param block table A Pandoc block element
---@return table|nil The speccompiler-toc Div, or nil if not found
local function find_toc_div(block)
    if block.t ~= "Div" then return nil end
    -- Direct: block itself has the class
    if has_class(block, "speccompiler-toc") then return block end
    -- Wrapped: block is a wrapper Div containing a single speccompiler-toc Div
    local content = block.content or {}
    if #content == 1 and content[1].t == "Div" and has_class(content[1], "speccompiler-toc") then
        return content[1]
    end
    return nil
end

---Check if block is a cover-section-start marker.
---@param block table Pandoc block element
---@return boolean
local function is_cover_start(block)
    return block.t == "RawBlock" and block.format == "speccompiler"
        and block.text == "cover-section-start"
end

---Check if a Div is a spec-title Div (possibly wrapped by sourcepos).
---@param block table Pandoc block element
---@return boolean
local function is_spec_title(block)
    if block.t ~= "Div" then return false end
    if has_class(block, "spec-title") then return true end
    local content = block.content or {}
    if #content == 1 and content[1].t == "Div" and has_class(content[1], "spec-title") then
        return true
    end
    return false
end

-- Pass 0: Pre-processing via Pandoc document-level handler.
-- Handles TOC conversion and strips spec-title when cover follows.
-- Needs document-level access to detect adjacent top-level block patterns.
local FILTER_PASS0_PRE = {
    Pandoc = function(doc)
        local blocks = doc.blocks
        local new_blocks = {}
        local i = 1
        while i <= #blocks do
            local block = blocks[i]

            -- Strip spec-title Div when followed by a cover section
            if is_spec_title(block) then
                local has_cover = false
                for j = i + 1, math.min(i + 3, #blocks) do
                    if is_cover_start(blocks[j]) then
                        has_cover = true
                        break
                    end
                end
                if has_cover then
                    i = i + 1
                    goto continue
                end
            end

            -- Check for Header followed by speccompiler-toc Div (direct or wrapped)
            if block.t == "Header" and i < #blocks then
                local toc_div = find_toc_div(blocks[i + 1])
                if toc_div then
                    local heading_text = pandoc.utils.stringify(block.content)
                    local toc_blocks = convert_toc_div(toc_div, heading_text)
                    for _, b in ipairs(toc_blocks) do
                        table.insert(new_blocks, b)
                    end
                    i = i + 2
                    goto continue
                end
            end
            -- Standalone speccompiler-toc Div (no preceding header)
            local toc_div = find_toc_div(block)
            if toc_div then
                local toc_blocks = convert_toc_div(toc_div, nil)
                for _, b in ipairs(toc_blocks) do
                    table.insert(new_blocks, b)
                end
                i = i + 1
                goto continue
            end
            table.insert(new_blocks, block)
            i = i + 1
            ::continue::
        end
        return pandoc.Pandoc(new_blocks, doc.meta)
    end
}

-- Pass 1: Div containers must be processed first.
-- Equation and caption Divs inspect inner speccompiler RawBlocks;
-- bottom-up traversal in a single pass would convert those RawBlocks
-- before the Div handler sees them, breaking extraction.
local FILTER_PASS1 = {
    Div = function(div)
        if has_class(div, "speccompiler-caption") then
            return convert_caption_div(div)
        elseif has_class(div, "speccompiler-numbered-equation") then
            return convert_equation_div(div)
        elseif has_class(div, "speccompiler-table") then
            return convert_table_div(div)
        elseif has_class(div, "spec-object-header") then
            return convert_spec_object_header_div(div)
        end

        -- Cover page semantic divs -> styled OOXML paragraphs
        for _, class in ipairs(div.classes or {}) do
            local style = COVER_CLASS_MAP[class]
            if style then
                local text = pandoc.utils.stringify(div.content)
                return pandoc.RawBlock("openxml", ooxml_styled_para(text, style))
            end
        end

        -- Pass through other Divs unchanged
        return div
    end,
}

-- Pass 2: Individual elements (RawBlocks now safe to convert)
local FILTER_PASS2 = {
    RawBlock = function(block)
        if block.format == "speccompiler" then
            return convert_speccompiler_block(block)
        end
        -- Pass through other RawBlocks unchanged
        return block
    end,

    RawInline = function(inline)
        if inline.format == "speccompiler" then
            return convert_speccompiler_inline(inline)
        end
        -- Pass through other RawInlines unchanged
        return inline
    end,

    Link = function(link)
        return replace_ext_placeholder(link)
    end
}

-- ============================================================================
-- Module API (used by emitter via writer.load_filter)
-- ============================================================================

local M = {}

---Process document blocks by directly iterating doc.blocks.
---Handles TOC conversion and strips spec-title when cover follows.
---Cannot use doc:walk() because Pandoc/Blocks handlers aren't supported there.
---@param doc table Pandoc document
---@return table Modified Pandoc document
local function apply_pre_pass(doc)
    local blocks = doc.blocks
    local new_blocks = {}
    local i = 1
    while i <= #blocks do
        local block = blocks[i]

        -- Strip spec-title Div when followed by a cover section
        -- (cover handler renders its own title with CoverTitle style)
        if is_spec_title(block) then
            -- Look ahead for cover-section-start (may be separated by bookmark markers)
            local has_cover = false
            for j = i + 1, math.min(i + 3, #blocks) do
                if is_cover_start(blocks[j]) then
                    has_cover = true
                    break
                end
            end
            if has_cover then
                i = i + 1
                goto continue
            end
        end

        -- Check for Header followed by speccompiler-toc Div (direct or wrapped)
        if block.t == "Header" and i < #blocks then
            local toc_div = find_toc_div(blocks[i + 1])
            if toc_div then
                local heading_text = pandoc.utils.stringify(block.content)
                local toc_blocks = convert_toc_div(toc_div, heading_text)
                for _, b in ipairs(toc_blocks) do
                    table.insert(new_blocks, b)
                end
                i = i + 2
                goto continue
            end
        end
        -- Standalone speccompiler-toc Div (no preceding header)
        local toc_div = find_toc_div(block)
        if toc_div then
            local toc_blocks = convert_toc_div(toc_div, nil)
            for _, b in ipairs(toc_blocks) do
                table.insert(new_blocks, b)
            end
            i = i + 1
            goto continue
        end
        table.insert(new_blocks, block)
        i = i + 1
        ::continue::
    end
    return pandoc.Pandoc(new_blocks, doc.meta)
end

---Apply the default DOCX filter to a Pandoc document.
---Converts speccompiler format markers to OOXML.
---@param doc table Pandoc document
---@param _config table Configuration (unused)
---@param _log table Logger (unused)
---@return table Modified Pandoc document
function M.apply(doc, _config, _log)
    doc = apply_pre_pass(doc)
    return doc:walk(FILTER_PASS1):walk(FILTER_PASS2)
end

-- ============================================================================
-- Native Pandoc Filter (used when loaded via --lua-filter)
-- ============================================================================

if FORMAT then
    return {FILTER_PASS0_PRE, FILTER_PASS1, FILTER_PASS2}
end

return M
