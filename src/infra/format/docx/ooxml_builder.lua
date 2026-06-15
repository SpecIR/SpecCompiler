---OOXML Builder for SpecCompiler.
---
---Static helpers for inline OOXML generation. Trimmed to the surface actually
---consumed: `static.pageref_entry`, used by model pre-textual list generation
---(e.g. abnt's pretextual_lists.lua) to emit TOC/LOF/LOT entries as PAGEREF
---hyperlink paragraphs. The former stateful builder API and document/float
---assembly helpers were dead code from the pre-descriptor float chain and have
---been removed.
---
---@module ooxml_builder
local OoxmlBuilder = {}

-- Use central XML utilities
local xml = require("infra.format.xml")

OoxmlBuilder.static = {}

---Build field code run sequence (begin, instrText, separate, placeholder, end).
---@param instr string Field instruction text (e.g., " PAGEREF anchor \\h ")
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

return OoxmlBuilder
