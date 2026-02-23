---Header/Footer Builder for SpecCompiler DOCX Generation.
---Provides shared infrastructure for creating, registering, and wiring
---OOXML header and footer parts across templates.
---
---Templates provide content-specific builders (e.g., logo tables, page numbering
---styles). This module handles the wiring: content types, relationships, sectPr
---references, field codes, file I/O, and part relationship files.
---@module header_builder

local xml = require("infra.format.xml")

local M = {}

-- ============================================================================
-- Constants
-- ============================================================================

---OOXML content types for header/footer parts.
M.HEADER_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
M.FOOTER_CONTENT_TYPE = "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"

---OOXML relationship types for header/footer parts.
M.HEADER_REL_TYPE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/header"
M.FOOTER_REL_TYPE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/footer"

---Basic header/footer namespaces (text only).
M.HDR_NAMESPACES = {
    ["xmlns:w"] = "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    ["xmlns:r"] = "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}

---Extended header/footer namespaces (with drawing support for logos/images).
M.HDR_NAMESPACES_DRAWING = {
    ["xmlns:w"]   = "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    ["xmlns:r"]   = "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    ["xmlns:wp"]  = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing",
    ["xmlns:a"]   = "http://schemas.openxmlformats.org/drawingml/2006/main",
    ["xmlns:pic"] = "http://schemas.openxmlformats.org/drawingml/2006/picture",
}

---Relationship namespace for package relationships.
local RELS_NAMESPACE = "http://schemas.openxmlformats.org/package/2006/relationships"

---XML declaration prefix for standalone part files.
local XML_DECLARATION = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

-- ============================================================================
-- Field Code Construction
-- ============================================================================

---Build a Word field code run sequence (begin/instrText/separate/placeholder/end).
---Used for PAGE, NUMPAGES, DATE, and other Word field codes.
---@param instr_text string Field instruction (e.g., " PAGE ", " NUMPAGES ")
---@param style string|nil Optional character style to apply (e.g., "PageNumber")
---@return table[] Array of w:r nodes
function M.build_field_runs(instr_text, style)
    local function make_rPr()
        if not style then return nil end
        return xml.node("w:rPr", {}, {
            xml.node("w:rStyle", {["w:val"] = style})
        })
    end

    local function run_with_rPr(children)
        local run_kids = {}
        local rPr = make_rPr()
        if rPr then run_kids[#run_kids + 1] = rPr end
        for _, c in ipairs(children) do
            run_kids[#run_kids + 1] = c
        end
        return xml.node("w:r", {}, run_kids)
    end

    -- Separate run for the placeholder value gets noProof in addition to style
    local placeholder_rPr_kids = {}
    if style then
        placeholder_rPr_kids[#placeholder_rPr_kids + 1] = xml.node("w:rStyle", {["w:val"] = style})
    end
    placeholder_rPr_kids[#placeholder_rPr_kids + 1] = xml.node("w:noProof")

    return {
        run_with_rPr({xml.node("w:fldChar", {["w:fldCharType"] = "begin"})}),
        run_with_rPr({xml.node("w:instrText", {["xml:space"] = "preserve"}, {xml.text(instr_text)})}),
        run_with_rPr({xml.node("w:fldChar", {["w:fldCharType"] = "separate"})}),
        xml.node("w:r", {}, {
            xml.node("w:rPr", {}, placeholder_rPr_kids),
            xml.node("w:t", {}, {xml.text("1")}),
        }),
        run_with_rPr({xml.node("w:fldChar", {["w:fldCharType"] = "end"})}),
    }
end

-- ============================================================================
-- Header/Footer XML Construction
-- ============================================================================

---Build a complete header XML document with XML declaration.
---@param namespaces table Namespace attributes for w:hdr element
---@param body_nodes table[] Array of child nodes (paragraphs, tables, etc.)
---@return string Complete header XML with declaration
function M.build_header_xml(namespaces, body_nodes)
    local hdr = xml.node("w:hdr", namespaces, body_nodes)
    return XML_DECLARATION .. xml.serialize_element(hdr)
end

---Build a complete footer XML document with XML declaration.
---@param namespaces table Namespace attributes for w:ftr element
---@param body_nodes table[] Array of child nodes (paragraphs, etc.)
---@return string Complete footer XML with declaration
function M.build_footer_xml(namespaces, body_nodes)
    local ftr = xml.node("w:ftr", namespaces, body_nodes)
    return XML_DECLARATION .. xml.serialize_element(ftr)
end

---Build an empty header (single empty paragraph with Header style).
---Common pattern used by both ABNT (first/even pages) and other templates.
---@param namespaces table|nil Namespace attributes (defaults to HDR_NAMESPACES)
---@return string Complete header XML with declaration
function M.build_empty_header(namespaces)
    namespaces = namespaces or M.HDR_NAMESPACES
    return M.build_header_xml(namespaces, {
        xml.node("w:p", {}, {
            xml.node("w:pPr", {}, {
                xml.node("w:pStyle", {["w:val"] = "Header"}),
            }),
        })
    })
end

---Build a simple page-number header (paragraph with PAGE field and alignment).
---@param alignment string Justification value ("left", "right", "center")
---@param namespaces table|nil Namespace attributes (defaults to HDR_NAMESPACES)
---@return string Complete header XML with declaration
function M.build_page_number_header(alignment, namespaces)
    namespaces = namespaces or M.HDR_NAMESPACES
    local children = {
        xml.node("w:pPr", {}, {
            xml.node("w:pStyle", {["w:val"] = "Header"}),
            xml.node("w:jc", {["w:val"] = alignment}),
        }),
    }
    for _, r in ipairs(M.build_field_runs(" PAGE ")) do
        children[#children + 1] = r
    end
    return M.build_header_xml(namespaces, {
        xml.node("w:p", {}, children)
    })
end

-- ============================================================================
-- Part Relationship Files
-- ============================================================================

---Build a relationship file for a header/footer part.
---Used when headers reference embedded media (e.g., logo images).
---@param relationships table[] Array of {id, type, target} tables
---@return string Complete relationships XML with declaration
function M.build_part_rels(relationships)
    local children = {}
    for _, rel in ipairs(relationships) do
        children[#children + 1] = xml.node("Relationship", {
            ["Id"] = rel.id,
            ["Type"] = rel.type,
            ["Target"] = rel.target,
        })
    end
    local rels = xml.node("Relationships", {["xmlns"] = RELS_NAMESPACE}, children)
    return XML_DECLARATION .. xml.serialize_element(rels)
end

-- ============================================================================
-- Content Type Registration ([Content_Types].xml)
-- ============================================================================

---Register header/footer parts in [Content_Types].xml.
---Uses DOM parsing for robust manipulation. Idempotent: skips already-registered parts.
---@param content string [Content_Types].xml content
---@param parts table[] Array of {file, type} where type is "header" or "footer"
---@param log table Logger instance
---@return string Modified [Content_Types].xml content
function M.register_content_types(content, parts, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then
        return content
    end

    local types_root = doc.root

    -- Build set of existing overrides
    local existing = {}
    for _, kid in ipairs(types_root.kids or {}) do
        if kid.name == "Override" then
            local part = xml.get_attr(kid, "PartName")
            if part then existing[part] = true end
        end
    end

    local added = 0
    for _, part in ipairs(parts) do
        local part_name = "/word/" .. part.file
        if not existing[part_name] then
            local ct = part.type == "footer" and M.FOOTER_CONTENT_TYPE or M.HEADER_CONTENT_TYPE
            xml.add_child(types_root, xml.node("Override", {
                ["PartName"] = part_name,
                ["ContentType"] = ct,
            }))
            added = added + 1
        end
    end

    if added > 0 then
        log.debug('[HEADER-BUILDER] Registered %d content type(s)', added)
    end

    return xml.serialize(doc)
end

-- ============================================================================
-- Relationship Registration (document.xml.rels)
-- ============================================================================

---Register header/footer relationships in document.xml.rels.
---Supports two strategies:
---  - Fixed rIds: Each part specifies its own rid in the parts array
---  - Auto rIds: rIds are assigned sequentially from max_existing + 1
---Idempotent: skips relationships whose Target already exists.
---@param content string document.xml.rels content
---@param parts table[] Array of {file, type, rid?} where type is "header" or "footer"
---@param log table Logger instance
---@return string Modified document.xml.rels content
---@return table rid_map Map of file → assigned rId (useful for auto-assigned rIds)
function M.register_relationships(content, parts, log)
    local doc = xml.parse(content)
    if not doc or not doc.root then
        return content, {}
    end

    local rels_root = doc.root

    -- Build set of existing targets and find max rId for auto-assignment
    local existing_targets = {}
    local max_id = 0
    for _, kid in ipairs(rels_root.kids or {}) do
        if kid.name == "Relationship" then
            local id = xml.get_attr(kid, "Id")
            local target = xml.get_attr(kid, "Target")
            if id then
                local num = tonumber(id:match("^rId(%d+)$"))
                if num and num > max_id then max_id = num end
            end
            if target then existing_targets[target] = true end
        end
    end

    local rid_map = {}
    local next_id = max_id + 1
    local added = 0

    for _, part in ipairs(parts) do
        if not existing_targets[part.file] then
            -- Determine rId: use fixed if provided, otherwise auto-assign
            local rid
            if part.rid then
                rid = part.rid
            else
                rid = "rId" .. tostring(next_id)
                next_id = next_id + 1
            end

            local rel_type = part.type == "footer" and M.FOOTER_REL_TYPE or M.HEADER_REL_TYPE
            xml.add_child(rels_root, xml.node("Relationship", {
                ["Id"] = rid,
                ["Type"] = rel_type,
                ["Target"] = part.file,
            }))
            rid_map[part.file] = rid
            added = added + 1
        else
            -- Already exists — find its rId for the map
            for _, kid in ipairs(rels_root.kids or {}) do
                if kid.name == "Relationship" then
                    local target = xml.get_attr(kid, "Target")
                    if target == part.file then
                        rid_map[part.file] = xml.get_attr(kid, "Id")
                        break
                    end
                end
            end
        end
    end

    if added > 0 then
        log.debug('[HEADER-BUILDER] Registered %d relationship(s)', added)
    end

    return xml.serialize(doc), rid_map
end

-- ============================================================================
-- Section Property References (document.xml)
-- ============================================================================

---Inject header/footer references into all sectPr elements in document.xml.
---Each reference specifies a type ("first", "default", "even") and rId.
---Idempotent: skips references that already exist.
---@param content string document.xml content
---@param references table[] Array of {type, rid, element} tables
---  type: "first", "default", or "even"
---  rid: relationship ID (e.g., "rId9100")
---  element: "header" or "footer" (defaults to "header")
---@param log table Logger instance
---@param options table|nil Optional settings
---  title_pg: boolean — add w:titlePg if missing (default true)
---@return string Modified document.xml content
function M.inject_section_references(content, references, log, options)
    options = options or {}
    local add_title_pg = options.title_pg ~= false

    local doc = xml.parse(content)
    if not doc or not doc.root then
        return content
    end

    local body = xml.find_child(doc.root, "w:body")
    if not body then
        return content
    end

    local sectPrs = xml.find_by_name(body, "w:sectPr")
    local count = 0

    for _, sectPr in ipairs(sectPrs) do
        -- Build set of existing references
        local existing = {}
        local has_titlePg = false
        for _, kid in ipairs(sectPr.kids or {}) do
            if kid.name == "w:headerReference" then
                local hdr_type = xml.get_attr(kid, "w:type")
                if hdr_type then existing["header:" .. hdr_type] = true end
            elseif kid.name == "w:footerReference" then
                local ftr_type = xml.get_attr(kid, "w:type")
                if ftr_type then existing["footer:" .. ftr_type] = true end
            elseif kid.name == "w:titlePg" then
                has_titlePg = true
            end
        end

        -- Add missing references
        for _, ref in ipairs(references) do
            local element = ref.element or "header"
            local key = element .. ":" .. ref.type
            if not existing[key] then
                local tag = element == "footer" and "w:footerReference" or "w:headerReference"
                xml.insert_child(sectPr, xml.node(tag, {
                    ["w:type"] = ref.type,
                    ["r:id"] = ref.rid,
                }), 1)
                count = count + 1
            end
        end

        -- Add titlePg if any "first" type reference exists and titlePg is missing
        if add_title_pg and not has_titlePg then
            local has_first = false
            for _, ref in ipairs(references) do
                if ref.type == "first" then has_first = true; break end
            end
            if has_first then
                xml.add_child(sectPr, xml.node("w:titlePg"))
            end
        end
    end

    if count > 0 then
        log.debug('[HEADER-BUILDER] Injected %d reference(s) into sectPr elements', count)
    end

    return xml.serialize(doc)
end

-- ============================================================================
-- File I/O
-- ============================================================================

---Write header/footer part files to the extracted DOCX directory.
---Also writes part relationship files and copies media files if specified.
---@param temp_dir string Path to extracted DOCX temp directory
---@param parts table[] Array of part definitions:
---  file: string — filename (e.g., "header1.xml")
---  content: string — XML content to write
---  rels: string|nil — Optional _rels file content
---  media: table[]|nil — Optional array of {source, dest} for media files
---@param log table Logger instance
function M.write_parts(temp_dir, parts, log)
    local word_dir = temp_dir .. "/word"

    for _, part in ipairs(parts) do
        -- Write the part file
        local path = word_dir .. "/" .. part.file
        local f = io.open(path, "w")
        if f then
            f:write(part.content)
            f:close()
            log.debug('[HEADER-BUILDER] Created %s', part.file)
        else
            log.warn('[HEADER-BUILDER] Failed to create %s', part.file)
        end

        -- Write part relationship file if provided
        if part.rels then
            local rels_dir = word_dir .. "/_rels"
            os.execute('mkdir -p "' .. rels_dir .. '"')
            local rels_path = rels_dir .. "/" .. part.file .. ".rels"
            local rf = io.open(rels_path, "w")
            if rf then
                rf:write(part.rels)
                rf:close()
                log.debug('[HEADER-BUILDER] Created _rels/%s.rels', part.file)
            end
        end

        -- Copy media files if specified
        if part.media then
            local media_dir = word_dir .. "/media"
            os.execute('mkdir -p "' .. media_dir .. '"')
            for _, m in ipairs(part.media) do
                local src = io.open(m.source, "rb")
                if src then
                    local data = src:read("*a")
                    src:close()
                    local dst = io.open(media_dir .. "/" .. m.dest, "wb")
                    if dst then
                        dst:write(data)
                        dst:close()
                        log.debug('[HEADER-BUILDER] Copied media/%s', m.dest)
                    end
                else
                    log.warn('[HEADER-BUILDER] Media source not found: %s', m.source)
                end
            end
        end
    end
end

return M
