---Config-driven heading numbering for DOCX postprocessors.
---Handles both numbering.xml injection and document.xml numPr application.
---
---Extracts the duplicated heading numbering logic from EMB and ABNT
---postprocessors into a single reusable module. Callers provide numbering
---definitions (abstractNum + num pairs) and heading-to-numbering mappings
---as plain config tables; this module handles all XML DOM manipulation.
---
---@module heading_numberer

local xml = require("infra.format.xml")

local M = {}

-- ============================================================================
-- Internal Helpers
-- ============================================================================

---Find an abstractNum element by its w:abstractNumId attribute value.
---@param numbering_root table The w:numbering root element
---@param id string The abstractNumId value to search for
---@return table|nil Matching element or nil
local function find_abstract_num(numbering_root, id)
    local abstract_nums = xml.find_children(numbering_root, "w:abstractNum")
    for _, an in ipairs(abstract_nums) do
        if xml.get_attr(an, "w:abstractNumId") == id then
            return an
        end
    end
    return nil
end

---Find a num element by its w:numId attribute value.
---@param numbering_root table The w:numbering root element
---@param id string The numId value to search for
---@return table|nil Matching element or nil
local function find_num(numbering_root, id)
    local nums = xml.find_children(numbering_root, "w:num")
    for _, n in ipairs(nums) do
        if xml.get_attr(n, "w:numId") == id then
            return n
        end
    end
    return nil
end

---Build a w:lvl element from a level definition table.
---@param level table Level config: { ilvl, start, num_fmt, lvl_text, lvl_jc,
---                    indent, suffix, restart_level, pstyle }
---@return table XML element node for w:lvl
local function build_level(level)
    local children = {}

    -- w:start
    table.insert(children, xml.node("w:start", {
        ["w:val"] = level.start or "1"
    }))

    -- w:numFmt
    table.insert(children, xml.node("w:numFmt", {
        ["w:val"] = level.num_fmt or "decimal"
    }))

    -- w:pStyle (links this level to a paragraph style, so Word auto-numbers)
    if level.pstyle then
        table.insert(children, xml.node("w:pStyle", {
            ["w:val"] = level.pstyle
        }))
    end

    -- w:lvlRestart (optional, only when restarting on a higher level change)
    if level.restart_level then
        table.insert(children, xml.node("w:lvlRestart", {
            ["w:val"] = tostring(level.restart_level)
        }))
    end

    -- w:suff (tab, space, or nothing)
    if level.suffix then
        table.insert(children, xml.node("w:suff", {
            ["w:val"] = level.suffix
        }))
    end

    -- w:lvlText
    table.insert(children, xml.node("w:lvlText", {
        ["w:val"] = level.lvl_text or ""
    }))

    -- w:lvlJc
    table.insert(children, xml.node("w:lvlJc", {
        ["w:val"] = level.lvl_jc or "left"
    }))

    -- w:pPr with w:ind (paragraph indentation)
    local indent = level.indent or {}
    table.insert(children, xml.node("w:pPr", {}, {
        xml.node("w:ind", {
            ["w:left"]    = indent.left    or "0",
            ["w:hanging"] = indent.hanging or "0"
        })
    }))

    return xml.node("w:lvl", {["w:ilvl"] = tostring(level.ilvl)}, children)
end

---Build a w:abstractNum element from a numbering definition.
---@param def table Numbering definition with abstract_num_id, nsid, tmpl,
---                  name, multi_level_type, and levels
---@return table XML element node for w:abstractNum
local function build_abstract_num(def)
    local children = {
        xml.node("w:nsid",           {["w:val"] = def.nsid}),
        xml.node("w:multiLevelType", {["w:val"] = def.multi_level_type or "multilevel"}),
        xml.node("w:tmpl",           {["w:val"] = def.tmpl}),
    }

    if def.name then
        table.insert(children, xml.node("w:name", {["w:val"] = def.name}))
    end

    for _, level in ipairs(def.levels or {}) do
        table.insert(children, build_level(level))
    end

    return xml.node("w:abstractNum", {
        ["w:abstractNumId"] = def.abstract_num_id
    }, children)
end

---Build a w:num element linking to an abstractNum.
---@param num_id string The numId value
---@param abstract_num_id string The abstractNumId to reference
---@return table XML element node for w:num
local function build_num(num_id, abstract_num_id)
    return xml.node("w:num", {["w:numId"] = num_id}, {
        xml.node("w:abstractNumId", {["w:val"] = abstract_num_id})
    })
end

-- ============================================================================
-- Public API
-- ============================================================================

---Merge numbering definitions into numbering.xml.
---
---For each definition, removes any existing abstractNum/num with the same IDs
---before inserting. AbstractNum elements are inserted at the beginning of the
---numbering root (in order); num elements are appended at the end.
---
---Also cleans up malformed abstractNum elements that lack a w:abstractNumId.
---
---@param content string numbering.xml content
---@param definitions table Array of numbering definitions:
---   Each: { abstract_num_id: string, nsid: string, tmpl: string, name: string,
---           multi_level_type: string, levels: table, num_id: string }
---   Level: { ilvl: number, start: string, num_fmt: string, lvl_text: string,
---            lvl_jc: string, indent: table, suffix: string, restart_level: number|nil }
---@param log table Logger instance
---@return string Modified numbering.xml content
function M.merge_numbering(content, definitions, log)
    if not definitions or #definitions == 0 then
        log.warning("[HEADING-NUMBERER] No numbering definitions provided")
        return content
    end

    local doc = xml.parse(content)
    if not doc or not doc.root then
        log.warning("[HEADING-NUMBERER] Failed to parse numbering.xml")
        return content
    end

    local numbering_root = doc.root
    if numbering_root.name ~= "numbering" then
        numbering_root = xml.find_child(doc.root, "w:numbering") or doc.root
    end

    -- Clean up malformed abstractNum elements (no abstractNumId attribute)
    local abstract_nums = xml.find_children(numbering_root, "w:abstractNum")
    for _, an in ipairs(abstract_nums) do
        if not xml.get_attr(an, "w:abstractNumId") then
            xml.remove_child(numbering_root, an)
        end
    end

    -- Check for idempotency: if the first definition's nsid already exists
    -- in the matching abstractNum, the numbering was already merged.
    local first_def = definitions[1]
    local probe = find_abstract_num(numbering_root, first_def.abstract_num_id)
    if probe then
        local nsid = xml.find_child(probe, "w:nsid")
        if nsid and xml.get_attr(nsid, "w:val") == first_def.nsid then
            log.debug("[HEADING-NUMBERER] Numbering already present (nsid=%s), skipping",
                      first_def.nsid)
            return content
        end
    end

    -- Build and insert each definition
    local abstract_nodes = {}
    local num_nodes = {}

    for _, def in ipairs(definitions) do
        -- Remove existing abstractNum with same ID
        local existing_abstract = find_abstract_num(numbering_root, def.abstract_num_id)
        if existing_abstract then
            xml.remove_child(numbering_root, existing_abstract)
        end

        -- Remove existing num with same ID
        local existing_num = find_num(numbering_root, def.num_id)
        if existing_num then
            xml.remove_child(numbering_root, existing_num)
        end

        table.insert(abstract_nodes, build_abstract_num(def))
        table.insert(num_nodes, build_num(def.num_id, def.abstract_num_id))
    end

    -- Insert abstractNum elements at the beginning (in definition order)
    for i = #abstract_nodes, 1, -1 do
        xml.insert_child(numbering_root, abstract_nodes[i], 1)
    end

    -- Append num elements at the end
    for _, num_node in ipairs(num_nodes) do
        xml.add_child(numbering_root, num_node)
    end

    log.debug("[HEADING-NUMBERER] Merged %d numbering definition(s)", #definitions)
    return xml.serialize(doc)
end

---Apply heading numbering to paragraphs in document.xml.
---
---Scans all w:p elements for w:pStyle matching the heading_map keys.
---For each match that does not already have a w:numPr, inserts one
---immediately after the w:pStyle element inside w:pPr.
---
---@param content string document.xml content
---@param heading_map table Maps style ID to { ilvl: string, numId: string }
---   e.g., { Heading1 = {ilvl="0", numId="1"}, Heading2 = {ilvl="1", numId="1"} }
---@param log table Logger instance
---@return string Modified document.xml content
function M.apply_numbering(content, heading_map, log)
    if not heading_map or not next(heading_map) then
        log.warning("[HEADING-NUMBERER] No heading map provided")
        return content
    end

    local doc = xml.parse(content)
    if not doc or not doc.root then
        log.warning("[HEADING-NUMBERER] Failed to parse document.xml")
        return content
    end

    local count = 0
    local paras = xml.find_by_name(doc.root, "w:p")

    for _, p in ipairs(paras) do
        local pPr = xml.find_child(p, "w:pPr")
        if pPr then
            local pStyle = xml.find_child(pPr, "w:pStyle")
            if pStyle then
                local style_id = xml.get_attr(pStyle, "w:val")
                local config = heading_map[style_id]

                if config then
                    -- Skip if numPr already exists
                    local existing = xml.find_child(pPr, "w:numPr")
                    if not existing then
                        local numPr = xml.node("w:numPr", {}, {
                            xml.node("w:ilvl",  {["w:val"] = config.ilvl}),
                            xml.node("w:numId", {["w:val"] = config.numId})
                        })

                        -- Insert right after w:pStyle
                        local insert_pos = 2
                        for i, kid in ipairs(pPr.kids or {}) do
                            if kid.name == "pStyle" or
                               (kid.nsPrefix and kid.nsPrefix .. ":" .. kid.name == "w:pStyle") then
                                insert_pos = i + 1
                                break
                            end
                        end
                        xml.insert_child(pPr, numPr, insert_pos)
                        count = count + 1
                    end
                end
            end
        end
    end

    if count > 0 then
        log.debug("[HEADING-NUMBERER] Added numbering to %d heading paragraph(s)", count)
    end

    return xml.serialize(doc)
end

return M
