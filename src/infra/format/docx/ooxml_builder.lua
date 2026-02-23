---OOXML Builder for SpecCompiler.
---Unified OOXML builder for generating Word Open XML.
---
---Provides two APIs:
---1. Builder API (stateful): For document assembly with method chaining
---2. Static API (stateless): For inline OOXML generation
---
---@module ooxml_builder
local OoxmlBuilder = {}
OoxmlBuilder.__index = OoxmlBuilder

-- Use central XML utilities
local xml = require("infra.format.xml")

-- Export escape function for convenience
OoxmlBuilder.escape_xml = xml.escape

-- ============================================================================
-- Builder Core
-- ============================================================================

---Create a new OoxmlBuilder.
---@return OoxmlBuilder instance
function OoxmlBuilder.new()
    local self = setmetatable({}, OoxmlBuilder)
    self.nodes = {}
    self._bookmark_id = 0
    return self
end

---Generate unique bookmark ID.
---@return number Unique ID
function OoxmlBuilder:next_bookmark_id()
    self._bookmark_id = self._bookmark_id + 1
    return self._bookmark_id
end

-- ============================================================================
-- Internal Helpers
-- ============================================================================

---Build run properties node (w:rPr) from options.
---@param opts table Options: bold, italic, caps, style, font_cs, size, color
---@return table|nil w:rPr node or nil if no properties
local function build_rpr(opts)
    local children = {}
    if opts.font_cs then
        table.insert(children, xml.node("w:rFonts", { ["w:cs"] = opts.font_cs }))
    end
    if opts.bold then table.insert(children, xml.node("w:b")) end
    if opts.italic then table.insert(children, xml.node("w:i")) end
    if opts.caps then table.insert(children, xml.node("w:caps")) end
    if opts.color then
        table.insert(children, xml.node("w:color", { ["w:val"] = opts.color }))
    end
    if opts.size then
        table.insert(children, xml.node("w:sz", { ["w:val"] = tostring(opts.size) }))
        table.insert(children, xml.node("w:szCs", { ["w:val"] = tostring(opts.size) }))
    end
    if opts.style then
        table.insert(children, xml.node("w:rStyle", { ["w:val"] = opts.style }))
    end
    if #children > 0 then
        return xml.node("w:rPr", {}, children)
    end
    return nil
end

---Build a text run node (w:r) with optional formatting.
---@param text string Text content
---@param opts table Options: bold, italic, caps, style
---@return table w:r node
local function build_run(text, opts)
    opts = opts or {}
    local run_children = {}

    local rpr = build_rpr(opts)
    if rpr then table.insert(run_children, rpr) end

    table.insert(run_children, xml.node("w:t", { ["xml:space"] = "preserve" }, { xml.text(text) }))

    return xml.node("w:r", {}, run_children)
end

---Build paragraph properties node (w:pPr) from options.
---@param opts table Options: style, alignment, spacing_before, spacing_after, indent_left
---@return table|nil w:pPr node or nil if no properties
local function build_ppr(opts)
    local children = {}

    if opts.style then
        table.insert(children, xml.node("w:pStyle", { ["w:val"] = opts.style }))
    end

    if opts.indent_left then
        table.insert(children, xml.node("w:ind", { ["w:left"] = tostring(opts.indent_left) }))
    end

    if opts.alignment then
        table.insert(children, xml.node("w:jc", { ["w:val"] = opts.alignment }))
    end

    if opts.spacing_before or opts.spacing_after then
        local spacing_attrs = {}
        if opts.spacing_before then
            spacing_attrs["w:before"] = tostring(opts.spacing_before)
        end
        if opts.spacing_after then
            spacing_attrs["w:after"] = tostring(opts.spacing_after)
        end
        table.insert(children, xml.node("w:spacing", spacing_attrs))
    end

    if #children > 0 then
        return xml.node("w:pPr", {}, children)
    end
    return nil
end

-- ============================================================================
-- Builder Methods - Paragraph Building
-- ============================================================================

---Add a paragraph with optional style and text.
---@param opts table Options: text, style, alignment, spacing_before, spacing_after, etc.
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:para(opts)
    opts = opts or {}
    local children = {}

    local ppr = build_ppr(opts)
    if ppr then table.insert(children, ppr) end

    if opts.text then
        table.insert(children, build_run(opts.text, opts))
    end

    table.insert(self.nodes, xml.node("w:p", {}, children))
    return self
end

---Add an empty paragraph with spacing.
---@param twips number Spacing in twips (1 pt = 20 twips)
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:space(twips)
    local ppr = xml.node("w:pPr", {}, {
        xml.node("w:spacing", { ["w:before"] = tostring(twips) })
    })
    table.insert(self.nodes, xml.node("w:p", {}, { ppr }))
    return self
end

---Add a page break.
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:page_break()
    local run = xml.node("w:r", {}, {
        xml.node("w:br", { ["w:type"] = "page" })
    })
    table.insert(self.nodes, xml.node("w:p", {}, { run }))
    return self
end

---Add a section break.
---@param break_type string "continuous", "nextPage", "evenPage", "oddPage"
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:section_break(break_type)
    break_type = break_type or "nextPage"
    table.insert(self.nodes, xml.node("w:p"))
    local sectPr = xml.node("w:sectPr", {}, {
        xml.node("w:type", { ["w:val"] = break_type })
    })
    local ppr = xml.node("w:pPr", {}, { sectPr })
    table.insert(self.nodes, xml.node("w:p", {}, { ppr }))
    return self
end

-- ============================================================================
-- Builder Methods - Table Building
-- ============================================================================

---Add a table row.
---@param cells table Array of cell contents
---@param opts table Options: header, style
---@return table w:tr node
local function build_table_row(cells, opts)
    opts = opts or {}
    local row_children = {}

    for _, cell_content in ipairs(cells) do
        local cell_para = xml.node("w:p", {}, {
            build_run(tostring(cell_content), opts)
        })
        local cell = xml.node("w:tc", {}, { cell_para })
        table.insert(row_children, cell)
    end

    return xml.node("w:tr", {}, row_children)
end

---Add a table.
---@param rows table Array of row arrays
---@param opts table Options: header_rows, style
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:table(rows, opts)
    opts = opts or {}
    local tbl_children = {}

    -- Table properties
    local tblPr = xml.node("w:tblPr", {}, {
        xml.node("w:tblStyle", { ["w:val"] = opts.style or "TableGrid" }),
        xml.node("w:tblW", { ["w:w"] = "0", ["w:type"] = "auto" })
    })
    table.insert(tbl_children, tblPr)

    -- Add rows
    local header_rows = opts.header_rows or 0
    for i, row in ipairs(rows) do
        local row_opts = { header = i <= header_rows }
        table.insert(tbl_children, build_table_row(row, row_opts))
    end

    table.insert(self.nodes, xml.node("w:tbl", {}, tbl_children))
    return self
end

-- ============================================================================
-- Builder Methods - Bookmark Building
-- ============================================================================

---Add bookmark start element.
---@param id number Bookmark ID
---@param name string Bookmark name
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:bookmark_start(id, name)
    table.insert(self.nodes, xml.node("w:bookmarkStart", {
        ["w:id"] = tostring(id),
        ["w:name"] = name
    }))
    return self
end

---Add bookmark end element.
---@param id number Bookmark ID
---@return OoxmlBuilder self for chaining
function OoxmlBuilder:bookmark_end(id)
    table.insert(self.nodes, xml.node("w:bookmarkEnd", {
        ["w:id"] = tostring(id)
    }))
    return self
end

-- ============================================================================
-- Builder Methods - Serialization
-- ============================================================================

---Serialize all nodes to XML string.
---@return string XML content
function OoxmlBuilder:to_xml()
    local parts = {}
    for _, node in ipairs(self.nodes) do
        table.insert(parts, xml.serialize(node))
    end
    return table.concat(parts, "\n")
end

---Get nodes array.
---@return table Array of nodes
function OoxmlBuilder:get_nodes()
    return self.nodes
end

-- ============================================================================
-- Static API - Stateless OOXML Generation
-- ============================================================================

OoxmlBuilder.static = {}

---Build field code run sequence (begin, instrText, separate, placeholder, end).
---@param instr string Field instruction text (e.g., " SEQ Figure \\* ARABIC ")
---@param placeholder string|nil Placeholder text (default "0")
---@return table Array of w:r nodes
local function build_field_code(instr, placeholder)
    placeholder = placeholder or "0"
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

---Generate a caption paragraph with SEQ field.
---@param caption string Caption text
---@param type_ref string Float type (FIGURE, TABLE, etc.)
---@param number number|nil Explicit number (or nil for auto)
---@param opts table|nil Options: style, alignment, seq_name
---@return string OOXML string
function OoxmlBuilder.static.caption_para(caption, type_ref, number, opts)
    opts = opts or {}
    local style = opts.style or "Caption"
    local alignment = opts.alignment or "center"
    local seq_name = opts.seq_name or type_ref or "Figure"

    local children = {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = style}),
            xml.node("w:jc", {["w:val"] = alignment}),
        }),
    }

    -- Type prefix run
    table.insert(children, xml.node("w:r", {}, {
        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(seq_name .. " ")}),
    }))

    -- Number (SEQ field or literal)
    if number then
        table.insert(children, xml.node("w:r", {}, {
            xml.node("w:t", {}, {xml.text(tostring(number))}),
        }))
    else
        append_all(children, build_field_code(" SEQ " .. seq_name .. " \\* ARABIC "))
    end

    -- Separator and caption
    table.insert(children, xml.node("w:r", {}, {
        xml.node("w:t", {["xml:space"] = "preserve"}, {xml.text(": " .. (caption or ""))}),
    }))

    local p = xml.node("w:p", {}, children)
    return xml.serialize_element(p)
end

---Generate chapter-prefixed number (e.g., "2-1" for chapter 2, item 1).
---@param chapter number Chapter number
---@param item number Item number within chapter
---@param separator string Separator (default "-")
---@return string Formatted number
function OoxmlBuilder.static.chapter_prefixed_number(chapter, item, separator)
    separator = separator or "-"
    return string.format("%d%s%d", chapter or 1, separator, item or 1)
end

---Generate a TOC field.
---@param opts table|nil Options: depth, hyperlinks
---@return string OOXML string for TOC
function OoxmlBuilder.static.toc_field(opts)
    opts = opts or {}
    local depth = opts.depth or 3
    local hyperlinks = opts.hyperlinks ~= false

    local switches = string.format('TOC \\o "1-%d"', depth)
    if hyperlinks then
        switches = switches .. ' \\h'
    end

    local children = {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = "TOCHeading"}),
        }),
    }
    append_all(children, build_field_code(
        " " .. switches .. " ",
        "[Update field to generate table of contents]"
    ))

    local p = xml.node("w:p", {}, children)
    return xml.serialize_element(p)
end

---Generate a List of Figures/Tables field.
---@param type_ref string "Figure" or "Table"
---@param opts table|nil Options: heading_style
---@return string OOXML string
function OoxmlBuilder.static.list_field(type_ref, opts)
    opts = opts or {}
    local seq_name = type_ref or "Figure"

    local children = {}
    append_all(children, build_field_code(
        ' TOC \\c "' .. seq_name .. '" ',
        "[Update field to generate list]"
    ))

    local p = xml.node("w:p", {}, children)
    return xml.serialize_element(p)
end

---Generate a PAGEREF entry with hyperlink, text, tab leader, and page number.
---Used by TOC, LOF, LOT for manual list generation.
---@param opts table Options:
---  - anchor: string - Bookmark/identifier to link to
---  - text: string - Display text
---  - style: string - Paragraph style (default "TOC1")
---  - tab_pos: number - Tab position in twips (default 9350)
---  - leader: string - Tab leader type (default "dot")
---@return string OOXML paragraph
function OoxmlBuilder.static.pageref_entry(opts)
    local anchor = opts.anchor or ""
    local text = opts.text or ""
    local style = opts.style or "TOC1"
    local tab_pos = opts.tab_pos or 9350
    local leader = opts.leader or "dot"

    -- Build hyperlink children: text run, tab run, and PAGEREF field code runs
    local hyperlink_children = {
        xml.node("w:r", {}, {xml.node("w:t", {}, {xml.text(text)})}),
        xml.node("w:r", {}, {xml.node("w:tab")}),
    }
    append_all(hyperlink_children, build_field_code(
        " PAGEREF " .. anchor .. " \\h ",
        "1"
    ))

    local p = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = style}),
            xml.node("w:tabs", {}, {
                xml.node("w:tab", {["w:val"] = "right", ["w:leader"] = leader, ["w:pos"] = tostring(tab_pos)}),
            }),
        }),
        xml.node("w:hyperlink", {["w:anchor"] = anchor}, hyperlink_children),
    })
    return xml.serialize_element(p)
end

---Generate ABNT-formatted equation with right-aligned number.
---@param omml string OMML math content
---@param seq_name string Sequence name (e.g., "Equação")
---@param opts table|nil Options: number, identifier (for bookmark)
---@return string OOXML string
function OoxmlBuilder.static.equation_with_number(omml, seq_name, opts)
    opts = opts or {}
    local number = opts.number
    local identifier = opts.identifier

    -- Build number cell children (paragraph content for the right cell)
    local number_para_children = {
        xml.node("w:pPr", {}, {
            xml.node("w:jc", {["w:val"] = "right"}),
        }),
    }

    -- Optional bookmark for cross-references
    local bm_id
    if identifier then
        bm_id = 0
        for i = 1, #identifier do
            bm_id = (bm_id * 31 + identifier:byte(i)) % 100000
        end
        bm_id = bm_id + 1  -- Ensure non-zero
        table.insert(number_para_children, xml.node("w:bookmarkStart", {
            ["w:id"] = tostring(bm_id),
            ["w:name"] = identifier,
        }))
    end

    if number then
        table.insert(number_para_children, xml.node("w:r", {}, {
            xml.node("w:t", {}, {xml.text("(" .. tostring(number) .. ")")}),
        }))
    else
        table.insert(number_para_children, xml.node("w:r", {}, {
            xml.node("w:t", {}, {xml.text("(")}),
        }))
        append_all(number_para_children, build_field_code(
            " SEQ " .. (seq_name or "Equação") .. " \\* ARABIC "
        ))
        table.insert(number_para_children, xml.node("w:r", {}, {
            xml.node("w:t", {}, {xml.text(")")}),
        }))
    end

    if identifier then
        table.insert(number_para_children, xml.node("w:bookmarkEnd", {
            ["w:id"] = tostring(bm_id),
        }))
    end

    -- Build no-border table properties
    local border_names = {"w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV"}
    local border_children = {}
    for _, bname in ipairs(border_names) do
        table.insert(border_children, xml.node(bname, {["w:val"] = "none"}))
    end

    -- Center cell: equation (pre-formed OMML)
    local center_para_children = {
        xml.node("w:pPr", {}, {
            xml.node("w:jc", {["w:val"] = "center"}),
        }),
        xml.raw(omml or ""),
    }

    -- Three-column table: left spacer, centered equation, right-aligned number
    local tbl = xml.node("w:tbl", {}, {
        xml.node("w:tblPr", {}, {
            xml.node("w:tblW", {["w:w"] = "5000", ["w:type"] = "pct"}),
            xml.node("w:tblBorders", {}, border_children),
        }),
        xml.node("w:tr", {}, {
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = "1000", ["w:type"] = "pct"}),
                }),
                xml.node("w:p"),
            }),
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = "3000", ["w:type"] = "pct"}),
                }),
                xml.node("w:p", {}, center_para_children),
            }),
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = "1000", ["w:type"] = "pct"}),
                }),
                xml.node("w:p", {}, number_para_children),
            }),
        }),
    })
    return xml.serialize_element(tbl)
end

---Generate a complete OOXML table from parsed table data.
---@param parsed table Parsed table with headers, rows, aligns
---@param opts table|nil Options: caption, number, identifier, style, float_type
---@return string OOXML string
function OoxmlBuilder.static.table(parsed, opts)
    opts = opts or {}

    -- Table properties
    -- float_type is used by postprocessor to apply correct ABNT styling:
    --   "TABLE" -> IBGE three-line style (open borders)
    --   "LISTING" -> Quadro style (closed borders)
    local style = opts.style or "TableGrid"
    local float_type = opts.float_type or "TABLE"

    local border_names = {"w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV"}
    local border_children = {}
    for _, bname in ipairs(border_names) do
        table.insert(border_children, xml.node(bname, {["w:val"] = "single", ["w:sz"] = "4"}))
    end

    local tbl_children = {
        xml.node("w:tblPr", {}, {
            xml.node("w:tblStyle", {["w:val"] = style}),
            xml.node("w:tblW", {["w:w"] = "5000", ["w:type"] = "pct"}),
            xml.node("w:tblDescription", {["w:val"] = "speccompiler:" .. float_type}),
            xml.node("w:tblBorders", {}, border_children),
        }),
    }

    -- Header row (if present)
    -- Uses w:tblHeader so postprocessor can detect and style header rows
    if parsed.headers and #parsed.headers > 0 then
        local header_cells = {}
        for _, h in ipairs(parsed.headers) do
            table.insert(header_cells, xml.node("w:tc", {}, {
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:jc", {["w:val"] = "center"}),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:rPr", {}, {xml.node("w:b")}),
                        xml.node("w:t", {}, {xml.text(tostring(h))}),
                    }),
                }),
            }))
        end
        -- Add w:trPr with w:tblHeader to mark this as a header row
        local header_row_children = {
            xml.node("w:trPr", {}, {xml.node("w:tblHeader")}),
        }
        append_all(header_row_children, header_cells)
        table.insert(tbl_children, xml.node("w:tr", {}, header_row_children))
    end

    -- Data rows
    for _, row in ipairs(parsed.rows or {}) do
        local cells = {}
        for i, cell in ipairs(row) do
            local align = "left"
            if parsed.aligns and parsed.aligns[i] then
                align = parsed.aligns[i]
            end
            table.insert(cells, xml.node("w:tc", {}, {
                xml.node("w:p", {}, {
                    xml.node("w:pPr", {}, {
                        xml.node("w:jc", {["w:val"] = align}),
                    }),
                    xml.node("w:r", {}, {
                        xml.node("w:t", {}, {xml.text(tostring(cell))}),
                    }),
                }),
            }))
        end
        table.insert(tbl_children, xml.node("w:tr", {}, cells))
    end

    local tbl = xml.node("w:tbl", {}, tbl_children)
    local table_xml = xml.serialize_element(tbl)

    -- Add caption if provided
    if opts.caption and opts.caption ~= "" then
        local prefix = opts.caption_format or opts.prefix or "Table"
        local caption_para = OoxmlBuilder.static.caption_para(
            opts.caption,
            prefix,
            opts.number,
            { seq_name = prefix }
        )
        return caption_para .. table_xml
    end

    return table_xml
end

---Generate a full-page table with content bottom-aligned.
---Used for dedication and epigraph pages in ABNT.
---@param content string OOXML paragraph content to place at bottom
---@param opts table|nil Options: height (in twips, default 13800 ~= full page)
---@return string OOXML table
function OoxmlBuilder.static.bottom_aligned_page(content, opts)
    opts = opts or {}
    local height = opts.height or 13800  -- Approximately full page minus margins

    local tbl_border_names = {"w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV"}
    local tbl_border_children = {}
    for _, bname in ipairs(tbl_border_names) do
        table.insert(tbl_border_children, xml.node(bname, {["w:val"] = "nil"}))
    end

    local cell_border_names = {"w:top", "w:left", "w:bottom", "w:right"}
    local cell_border_children = {}
    for _, bname in ipairs(cell_border_names) do
        table.insert(cell_border_children, xml.node(bname, {["w:val"] = "nil"}))
    end

    local tbl = xml.node("w:tbl", {}, {
        xml.node("w:tblPr", {}, {
            xml.node("w:tblW", {["w:w"] = "5000", ["w:type"] = "pct"}),
            xml.node("w:tblBorders", {}, tbl_border_children),
            xml.node("w:tblCellMar", {}, {
                xml.node("w:top", {["w:type"] = "dxa", ["w:w"] = "57"}),
                xml.node("w:left", {["w:type"] = "dxa", ["w:w"] = "108"}),
                xml.node("w:bottom", {["w:type"] = "dxa", ["w:w"] = "57"}),
                xml.node("w:right", {["w:type"] = "dxa", ["w:w"] = "108"}),
            }),
        }),
        xml.node("w:tr", {}, {
            xml.node("w:trPr", {}, {
                xml.node("w:trHeight", {["w:val"] = tostring(height), ["w:hRule"] = "exact"}),
            }),
            xml.node("w:tc", {}, {
                xml.node("w:tcPr", {}, {
                    xml.node("w:tcW", {["w:w"] = "5000", ["w:type"] = "pct"}),
                    xml.node("w:vAlign", {["w:val"] = "bottom"}),
                    xml.node("w:tcBorders", {}, cell_border_children),
                }),
                xml.raw(content),
            }),
        }),
    })
    return xml.serialize_element(tbl)
end

---Generate section break paragraph.
---@param break_type string "continuous", "nextPage", "evenPage", "oddPage"
---@return string OOXML string
function OoxmlBuilder.static.section_break_para(break_type)
    break_type = break_type or "nextPage"
    local p = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:sectPr", {}, {
                xml.node("w:type", {["w:val"] = break_type}),
            }),
        }),
    })
    return xml.serialize_element(p)
end

---Generate image paragraph (inline - current default behavior).
---@param rel_id string Relationship ID for image
---@param width number Width in EMUs
---@param height number Height in EMUs
---@param alt_text string|nil Alt text
---@return string OOXML string
function OoxmlBuilder.static.image_para(rel_id, width, height, alt_text)
    alt_text = alt_text or ""

    local p = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:jc", {["w:val"] = "center"}),
        }),
        xml.node("w:r", {}, {
            xml.node("w:drawing", {}, {
                xml.node("wp:inline", {}, {
                    xml.node("wp:extent", {["cx"] = tostring(width), ["cy"] = tostring(height)}),
                    xml.node("wp:docPr", {["id"] = "1", ["name"] = alt_text}),
                    xml.node("a:graphic", {["xmlns:a"] = "http://schemas.openxmlformats.org/drawingml/2006/main"}, {
                        xml.node("a:graphicData", {["uri"] = "http://schemas.openxmlformats.org/drawingml/2006/picture"}, {
                            xml.node("pic:pic", {["xmlns:pic"] = "http://schemas.openxmlformats.org/drawingml/2006/picture"}, {
                                xml.node("pic:blipFill", {}, {
                                    xml.node("a:blip", {["r:embed"] = rel_id}),
                                }),
                                xml.node("pic:spPr", {}, {
                                    xml.node("a:xfrm", {}, {
                                        xml.node("a:ext", {["cx"] = tostring(width), ["cy"] = tostring(height)}),
                                    }),
                                }),
                            }),
                        }),
                    }),
                }),
            }),
        }),
    })
    return xml.serialize_element(p)
end

---Generate anchored drawing paragraph for positioned floats.
---Uses wp:anchor instead of wp:inline for text-flow-independent positioning.
---@param rel_id string Relationship ID for image
---@param width number Width in EMUs
---@param height number Height in EMUs
---@param alt_text string|nil Alt text
---@param position string Position specifier: "h" (here), "t" (top), "b" (bottom)
---@return string OOXML string
function OoxmlBuilder.static.drawing_anchored(rel_id, width, height, alt_text, position)
    alt_text = alt_text or ""
    position = position or "h"

    -- Determine vertical positioning based on specifier
    local v_relative, v_position_child
    if position == "t" then
        v_relative = "page"
        v_position_child = xml.node("wp:align", {}, {xml.text("top")})
    elseif position == "b" then
        v_relative = "page"
        v_position_child = xml.node("wp:align", {}, {xml.text("bottom")})
    else
        -- "h" = here, anchored to paragraph
        v_relative = "paragraph"
        v_position_child = xml.node("wp:posOffset", {}, {xml.text("0")})
    end

    local p = xml.node("w:p", {}, {
        xml.node("w:r", {}, {
            xml.node("w:drawing", {}, {
                xml.node("wp:anchor", {
                    ["distT"] = "0", ["distB"] = "0", ["distL"] = "0", ["distR"] = "0",
                    ["simplePos"] = "0", ["relativeHeight"] = "1", ["behindDoc"] = "0",
                    ["locked"] = "0", ["layoutInCell"] = "1", ["allowOverlap"] = "0",
                }, {
                    xml.node("wp:simplePos", {["x"] = "0", ["y"] = "0"}),
                    xml.node("wp:positionH", {["relativeFrom"] = "margin"}, {
                        xml.node("wp:align", {}, {xml.text("center")}),
                    }),
                    xml.node("wp:positionV", {["relativeFrom"] = v_relative}, {
                        v_position_child,
                    }),
                    xml.node("wp:extent", {["cx"] = tostring(width), ["cy"] = tostring(height)}),
                    xml.node("wp:wrapTopAndBottom"),
                    xml.node("wp:docPr", {["id"] = "1", ["name"] = alt_text}),
                    xml.node("a:graphic", {["xmlns:a"] = "http://schemas.openxmlformats.org/drawingml/2006/main"}, {
                        xml.node("a:graphicData", {["uri"] = "http://schemas.openxmlformats.org/drawingml/2006/picture"}, {
                            xml.node("pic:pic", {["xmlns:pic"] = "http://schemas.openxmlformats.org/drawingml/2006/picture"}, {
                                xml.node("pic:nvPicPr", {}, {
                                    xml.node("pic:cNvPr", {["id"] = "0", ["name"] = alt_text}),
                                    xml.node("pic:cNvPicPr"),
                                }),
                                xml.node("pic:blipFill", {}, {
                                    xml.node("a:blip", {["r:embed"] = rel_id}),
                                    xml.node("a:stretch", {}, {
                                        xml.node("a:fillRect"),
                                    }),
                                }),
                                xml.node("pic:spPr", {}, {
                                    xml.node("a:xfrm", {}, {
                                        xml.node("a:off", {["x"] = "0", ["y"] = "0"}),
                                        xml.node("a:ext", {["cx"] = tostring(width), ["cy"] = tostring(height)}),
                                    }),
                                    xml.node("a:prstGeom", {["prst"] = "rect"}, {
                                        xml.node("a:avLst"),
                                    }),
                                }),
                            }),
                        }),
                    }),
                }),
            }),
        }),
    })
    return xml.serialize_element(p)
end

---Generate floating table properties for positioned tables.
---Tables use w:tblpPr instead of wp:anchor for positioning.
---@param position string Position specifier: "h" (here), "t" (top), "b" (bottom)
---@return string OOXML tblpPr element to insert in tblPr
function OoxmlBuilder.static.table_position_props(position)
    position = position or "h"

    local vert_anchor, vert_spec
    if position == "t" then
        vert_anchor = "page"
        vert_spec = "top"
    elseif position == "b" then
        vert_anchor = "page"
        vert_spec = "bottom"
    else
        -- "h" = here, anchored to text
        vert_anchor = "text"
        vert_spec = "center"
    end

    local tblpPr = xml.node("w:tblpPr", {
        ["w:leftFromText"] = "180",
        ["w:rightFromText"] = "180",
        ["w:vertAnchor"] = vert_anchor,
        ["w:horzAnchor"] = "margin",
        ["w:tblpXSpec"] = "center",
        ["w:tblpYSpec"] = vert_spec,
    })
    return xml.serialize_element(tblpPr)
end

---Generate section break with page orientation change.
---Used for position="p" with orientation="landscape".
---@param orientation string "portrait" or "landscape"
---@param page_width number|nil Page width in twips (default A4)
---@param page_height number|nil Page height in twips (default A4)
---@return string OOXML section break paragraph
function OoxmlBuilder.static.section_break_orientation(orientation, page_width, page_height)
    orientation = orientation or "portrait"

    -- A4 dimensions in twips
    local portrait_w = page_width or 11906
    local portrait_h = page_height or 16838

    local w, h
    local pgSz_attrs
    if orientation == "landscape" then
        -- Swap dimensions for landscape
        w = portrait_h
        h = portrait_w
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h), ["w:orient"] = "landscape"}
    else
        w = portrait_w
        h = portrait_h
        pgSz_attrs = {["w:w"] = tostring(w), ["w:h"] = tostring(h)}
    end

    local p = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:sectPr", {}, {
                xml.node("w:pgSz", pgSz_attrs),
                xml.node("w:type", {["w:val"] = "nextPage"}),
            }),
        }),
    })
    return xml.serialize_element(p)
end

-- ============================================================================
-- Document Assembly Helpers
-- ============================================================================

---Build a full document.xml content.
---@param body_content string Body content (paragraphs, tables, etc.)
---@param opts table|nil Options: page_size, margins
---@return string Full document XML
function OoxmlBuilder.build_document_xml(body_content, opts)
    opts = opts or {}

    local page_w = opts.page_width or 11906  -- A4 width in twips
    local page_h = opts.page_height or 16838 -- A4 height in twips
    local margin_top = opts.margin_top or 1440
    local margin_right = opts.margin_right or 1440
    local margin_bottom = opts.margin_bottom or 1440
    local margin_left = opts.margin_left or 1440

    local doc = xml.node("w:document", {
        ["xmlns:w"] = "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
        ["xmlns:r"] = "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        ["xmlns:wp"] = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    }, {
        xml.node("w:body", {}, {
            xml.raw(body_content),
            xml.node("w:sectPr", {}, {
                xml.node("w:pgSz", {["w:w"] = tostring(page_w), ["w:h"] = tostring(page_h)}),
                xml.node("w:pgMar", {
                    ["w:top"] = tostring(margin_top),
                    ["w:right"] = tostring(margin_right),
                    ["w:bottom"] = tostring(margin_bottom),
                    ["w:left"] = tostring(margin_left),
                }),
            }),
        }),
    })
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' .. xml.serialize_element(doc)
end

---Build a paragraph for a spec_object (simplified).
---@param obj table Spec object row
---@return string OOXML paragraph
function OoxmlBuilder.build_object_paragraph(obj)
    local style_id = obj.type_ref or "Normal"
    local pid = obj.identifier or ""
    local title = obj.title or ""

    local p = xml.node("w:p", {}, {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = style_id}),
        }),
        xml.node("w:r", {}, {
            xml.node("w:t", {}, {xml.text(pid .. " " .. title)}),
        }),
    })
    return xml.serialize_element(p)
end

---Build a block for a spec_float (simplified).
---@param float table Float row
---@return string OOXML block
function OoxmlBuilder.build_float_block(float)
    local caption = float.caption or ""
    local number = float.number or ""
    local type_ref = float.type_ref or "FIGURE"

    return OoxmlBuilder.static.caption_para(caption, type_ref, number, {})
end

return OoxmlBuilder
