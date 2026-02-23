-- ReqIF Validator for SpecCompiler
-- Validates ReqIF files for well-formedness, required structure, referential
-- integrity, and content assertions.
-- Modeled on ooxml_validator.lua; uses infra.format.xml (SLAXML) for DOM parsing.

local M = {}

local xml = require("infra.format.xml")

-- ============================================================================
-- Internal helpers
-- ============================================================================

---Collect IDENTIFIER attributes from all elements matching a tag name.
---@param doc table Parsed DOM
---@param tag string Element tag name
---@return table Set of identifier strings
local function collect_identifiers(doc, tag)
    local ids = {}
    for _, el in ipairs(xml.find_by_name(doc, tag)) do
        local id = xml.get_attr(el, "IDENTIFIER")
        if id then ids[id] = true end
    end
    return ids
end

---Get a ref value by navigating to a child path and reading its text.
---ReqIF references are typically: <PARENT><CHILD-REF>id</CHILD-REF></PARENT>
---@param el table Element
---@param wrapper_tag string Wrapper element (e.g., "TYPE")
---@param ref_tag string Reference element (e.g., "SPEC-OBJECT-TYPE-REF")
---@return string|nil Referenced identifier
local function ref_at(el, wrapper_tag, ref_tag)
    local wrapper = xml.find_child(el, wrapper_tag)
    if not wrapper then return nil end
    local ref = xml.find_child(wrapper, ref_tag)
    if not ref then return nil end
    return xml.get_text(ref)
end

-- ============================================================================
-- Validation checks
-- ============================================================================

---Validate XML well-formedness and basic ReqIF structure.
---@param content string Raw XML content
---@return boolean pass
---@return table errors
---@return table|nil doc Parsed DOM (nil on parse failure)
function M.validate_wellformedness(content)
    local errors = {}

    if not content or content == "" then
        return false, {"ReqIF file is empty"}, nil
    end

    if not content:find("<%?xml", 1) then
        table.insert(errors, "Missing XML declaration")
    end

    local ok, doc = pcall(xml.parse, content)
    if not ok then
        return false, {"XML parse error: " .. tostring(doc)}, nil
    end

    -- Check for REQ-IF root element
    local root = xml.find_child(doc, "REQ-IF")
    if not root then
        table.insert(errors, "Missing REQ-IF root element")
        return #errors == 0, errors, doc
    end

    -- Check namespace
    local ns = xml.get_attr(root, "xmlns")
    if ns and not ns:find("reqif", 1, true) then
        table.insert(errors, "REQ-IF namespace does not contain 'reqif': " .. ns)
    end

    return #errors == 0, errors, doc
end

---Validate required ReqIF structural sections.
---@param doc table Parsed DOM
---@return boolean pass
---@return table errors
function M.validate_structure(doc)
    local errors = {}

    local root = xml.find_child(doc, "REQ-IF")
    if not root then
        return false, {"Missing REQ-IF root element"}
    end

    -- THE-HEADER section
    local the_header = xml.find_child(root, "THE-HEADER")
    if not the_header then
        table.insert(errors, "Missing THE-HEADER section")
    else
        local header = xml.find_child(the_header, "REQ-IF-HEADER")
        if not header then
            table.insert(errors, "Missing REQ-IF-HEADER inside THE-HEADER")
        else
            -- Check required header children
            local header_fields = {"REQ-IF-TOOL-ID", "SOURCE-TOOL-ID", "TITLE", "CREATION-TIME"}
            for _, field in ipairs(header_fields) do
                if not xml.find_child(header, field) then
                    table.insert(errors, "Missing header field: " .. field)
                end
            end
        end
    end

    -- CORE-CONTENT section
    local core = xml.find_child(root, "CORE-CONTENT")
    if not core then
        table.insert(errors, "Missing CORE-CONTENT section")
        return #errors == 0, errors
    end

    local content = xml.find_child(core, "REQ-IF-CONTENT")
    if not content then
        table.insert(errors, "Missing REQ-IF-CONTENT inside CORE-CONTENT")
        return #errors == 0, errors
    end

    -- Required content sections
    local sections = {"DATATYPES", "SPEC-TYPES", "SPEC-OBJECTS", "SPECIFICATIONS"}
    for _, section in ipairs(sections) do
        local el = xml.find_child(content, section)
        if not el then
            table.insert(errors, "Missing " .. section .. " section in REQ-IF-CONTENT")
        end
    end

    -- At least one datatype
    local datatypes = xml.find_by_name(doc, "DATATYPES")
    if #datatypes > 0 then
        local dt_children = datatypes[1].kids or {}
        local dt_count = 0
        for _, k in ipairs(dt_children) do
            if k.type == "element" then dt_count = dt_count + 1 end
        end
        if dt_count == 0 then
            table.insert(errors, "DATATYPES section is empty")
        end
    end

    -- At least one specification
    local specs = xml.find_by_name(doc, "SPECIFICATION")
    if #specs == 0 then
        table.insert(errors, "No SPECIFICATION elements found")
    end

    return #errors == 0, errors
end

---Validate referential integrity across ReqIF elements.
---@param doc table Parsed DOM
---@return boolean pass
---@return table errors
function M.validate_referential_integrity(doc)
    local errors = {}

    -- Collect all defined identifiers
    local spec_object_type_ids = collect_identifiers(doc, "SPEC-OBJECT-TYPE")
    local spec_relation_type_ids = collect_identifiers(doc, "SPEC-RELATION-TYPE")
    local spec_object_ids = collect_identifiers(doc, "SPEC-OBJECT")

    -- Check SPEC-OBJECT -> SPEC-OBJECT-TYPE references
    for _, obj in ipairs(xml.find_by_name(doc, "SPEC-OBJECT")) do
        local type_ref = ref_at(obj, "TYPE", "SPEC-OBJECT-TYPE-REF")
        if type_ref and not spec_object_type_ids[type_ref] then
            local obj_id = xml.get_attr(obj, "IDENTIFIER") or "?"
            table.insert(errors, "SPEC-OBJECT " .. obj_id
                .. " references unknown SPEC-OBJECT-TYPE: " .. type_ref)
        end
    end

    -- Check SPEC-RELATION references
    for _, rel in ipairs(xml.find_by_name(doc, "SPEC-RELATION")) do
        local rel_id = xml.get_attr(rel, "IDENTIFIER") or "?"

        -- Type reference
        local type_ref = ref_at(rel, "TYPE", "SPEC-RELATION-TYPE-REF")
        if type_ref and not spec_relation_type_ids[type_ref] then
            table.insert(errors, "SPEC-RELATION " .. rel_id
                .. " references unknown SPEC-RELATION-TYPE: " .. type_ref)
        end

        -- Source reference
        local source_ref = ref_at(rel, "SOURCE", "SPEC-OBJECT-REF")
        if source_ref and not spec_object_ids[source_ref] then
            table.insert(errors, "SPEC-RELATION " .. rel_id
                .. " SOURCE references unknown SPEC-OBJECT: " .. source_ref)
        end

        -- Target reference
        local target_ref = ref_at(rel, "TARGET", "SPEC-OBJECT-REF")
        if target_ref and not spec_object_ids[target_ref] then
            table.insert(errors, "SPEC-RELATION " .. rel_id
                .. " TARGET references unknown SPEC-OBJECT: " .. target_ref)
        end
    end

    -- Check hierarchy SPEC-OBJECT-REF values
    for _, hier in ipairs(xml.find_by_name(doc, "SPEC-HIERARCHY")) do
        local obj_ref_el = xml.find_child(hier, "OBJECT")
        if obj_ref_el then
            local ref = xml.find_child(obj_ref_el, "SPEC-OBJECT-REF")
            if ref then
                local ref_id = xml.get_text(ref)
                if ref_id and ref_id ~= "" and not spec_object_ids[ref_id] then
                    local hier_id = xml.get_attr(hier, "IDENTIFIER") or "?"
                    table.insert(errors, "SPEC-HIERARCHY " .. hier_id
                        .. " references unknown SPEC-OBJECT: " .. ref_id)
                end
            end
        end
    end

    return #errors == 0, errors
end

---Validate content against per-test assertions.
---@param doc table Parsed DOM
---@param content string Raw XML content (for text-based checks)
---@param assertions table Assertion table with optional keys:
---  min_spec_objects (number), min_relations (number),
---  expect_pids (string[]), expect_xhtml (boolean),
---  expect_enum_datatypes (string[]), expect_object_type_names (string[])
---@return boolean pass
---@return table errors
function M.validate_content(doc, content, assertions)
    local errors = {}
    if not assertions then return true, errors end

    -- Count spec objects
    local spec_objects = xml.find_by_name(doc, "SPEC-OBJECT")
    if assertions.min_spec_objects then
        if #spec_objects < assertions.min_spec_objects then
            table.insert(errors, string.format(
                "Expected at least %d SPEC-OBJECT(s), found %d",
                assertions.min_spec_objects, #spec_objects))
        end
    end

    -- Count relations
    local relations = xml.find_by_name(doc, "SPEC-RELATION")
    if assertions.min_relations then
        if #relations < assertions.min_relations then
            table.insert(errors, string.format(
                "Expected at least %d SPEC-RELATION(s), found %d",
                assertions.min_relations, #relations))
        end
    end

    -- Check PIDs in ReqIF.ForeignID attribute values
    if assertions.expect_pids then
        -- Collect all attribute values that look like ForeignID
        -- In ReqIF XML: <ATTRIBUTE-VALUE-STRING THE-VALUE="pid">
        --   <DEFINITION><ATTRIBUTE-DEFINITION-STRING-REF>...</ATTRIBUTE-DEFINITION-STRING-REF></DEFINITION>
        -- Simplest: search raw text for PID strings
        for _, pid in ipairs(assertions.expect_pids) do
            if not content:find(pid, 1, true) then
                table.insert(errors, "Expected PID not found in output: " .. pid)
            end
        end
    end

    -- Check XHTML content presence
    if assertions.expect_xhtml then
        -- Look for XHTML namespace or ATTRIBUTE-VALUE-XHTML elements
        local has_xhtml = content:find("ATTRIBUTE%-VALUE%-XHTML")
            or content:find("reqif%-xhtml")
            or content:find("xhtml:div")
            or content:find("xmlns:xhtml")
        if not has_xhtml then
            table.insert(errors, "Expected XHTML content but none found")
        end
    end

    -- Check enum datatypes exist
    if assertions.expect_enum_datatypes then
        for _, dt_name in ipairs(assertions.expect_enum_datatypes) do
            local found = false
            for _, dt_el in ipairs(xml.find_by_name(doc, "DATATYPE-DEFINITION-ENUMERATION")) do
                local ln = xml.get_attr(dt_el, "LONG-NAME")
                if ln and ln == dt_name then
                    -- Also verify it has enum values
                    local values = xml.find_by_name(dt_el, "ENUM-VALUE")
                    if #values > 0 then
                        found = true
                    else
                        table.insert(errors, "ENUM datatype " .. dt_name .. " has no values")
                    end
                    break
                end
            end
            if not found then
                table.insert(errors, "Expected ENUM datatype not found: " .. dt_name)
            end
        end
    end

    -- Check object type names
    if assertions.expect_object_type_names then
        local found_types = {}
        for _, sot in ipairs(xml.find_by_name(doc, "SPEC-OBJECT-TYPE")) do
            local ln = xml.get_attr(sot, "LONG-NAME")
            if ln then found_types[ln] = true end
        end
        for _, expected_name in ipairs(assertions.expect_object_type_names) do
            if not found_types[expected_name] then
                table.insert(errors, "Expected SPEC-OBJECT-TYPE not found: " .. expected_name)
            end
        end
    end

    return #errors == 0, errors
end

---Validate ReqIF file using Python reqif library (roundtrip check).
---Optional -- returns true if python3 or reqif is unavailable (non-blocking).
---@param reqif_path string Path to .reqif file
---@return boolean pass
---@return table errors
function M.validate_python_roundtrip(reqif_path)
    local errors = {}
    local cmd = string.format(
        'python3 -c "from reqif.parser import ReqIFParser; b = ReqIFParser.parse(\'%s\'); print(len(b.exceptions))" 2>&1',
        reqif_path:gsub("'", "'\\''")
    )
    local handle = io.popen(cmd)
    if not handle then
        -- Python not available, skip this check
        return true, {}
    end
    local output = handle:read("*a")
    local exit_ok = handle:close()

    if not exit_ok then
        table.insert(errors, "Python reqif parser failed: " .. (output or "unknown error"))
        return false, errors
    end

    local count = tonumber(output:match("^(%d+)"))
    if count and count > 0 then
        table.insert(errors, "Python reqif parser found " .. count .. " exception(s)")
        return false, errors
    end

    return true, errors
end

-- ============================================================================
-- Composite validation
-- ============================================================================

---Run all validation checks on a ReqIF file.
---@param reqif_path string Path to .reqif file
---@param assertions table|nil Content assertions (optional)
---@return boolean pass True if all checks pass
---@return table errors Array of prefixed error descriptions
function M.validate_reqif(reqif_path, assertions)
    -- Read file
    local f = io.open(reqif_path, "r")
    if not f then
        return false, {"File not found: " .. reqif_path}
    end
    local content = f:read("*a")
    f:close()

    if not content or content == "" then
        return false, {"File is empty: " .. reqif_path}
    end

    local all_errors = {}
    local all_pass = true

    -- 1. Well-formedness
    local wf_ok, wf_errors, doc = M.validate_wellformedness(content)
    if not wf_ok then
        all_pass = false
        for _, e in ipairs(wf_errors) do
            table.insert(all_errors, "[wellformedness] " .. e)
        end
    end
    if not doc then
        return false, all_errors
    end

    -- 2. Structure
    local struct_ok, struct_errors = M.validate_structure(doc)
    if not struct_ok then
        all_pass = false
        for _, e in ipairs(struct_errors) do
            table.insert(all_errors, "[structure] " .. e)
        end
    end

    -- 3. Referential integrity
    local ref_ok, ref_errors = M.validate_referential_integrity(doc)
    if not ref_ok then
        all_pass = false
        for _, e in ipairs(ref_errors) do
            table.insert(all_errors, "[referential_integrity] " .. e)
        end
    end

    -- 4. Content assertions
    if assertions then
        local content_ok, content_errors = M.validate_content(doc, content, assertions)
        if not content_ok then
            all_pass = false
            for _, e in ipairs(content_errors) do
                table.insert(all_errors, "[content] " .. e)
            end
        end
    end

    -- 5. Python roundtrip (optional, non-blocking)
    local py_ok, py_errors = M.validate_python_roundtrip(reqif_path)
    if not py_ok then
        all_pass = false
        for _, e in ipairs(py_errors) do
            table.insert(all_errors, "[python_roundtrip] " .. e)
        end
    end

    return all_pass, all_errors
end

return M
