-- OOXML Validator for SpecCompiler
-- Validates DOCX files for well-formedness, required parts, relationship
-- consistency, content type coverage, and namespace declarations.

local M = {}

local xml = require("infra.format.xml")

-- ============================================================================
-- Internal helpers
-- ============================================================================

---List all files in a DOCX (ZIP) archive.
---Uses `unzip -Z1` for clean, one-per-line output.
---@param docx_path string Path to DOCX file
---@return table Array of file paths inside the archive
local function list_archive_files(docx_path)
    local cmd = string.format('unzip -Z1 "%s" 2>/dev/null', docx_path)
    local handle = io.popen(cmd)
    if not handle then return {} end
    local files = {}
    for line in handle:lines() do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed and trimmed ~= "" then
            table.insert(files, trimmed)
        end
    end
    handle:close()
    return files
end

---Extract a file from a DOCX (ZIP) archive.
---@param docx_path string Path to DOCX file
---@param inner_path string Path within the DOCX
---@return string|nil content File contents or nil if not found
local function extract(docx_path, inner_path)
    -- Escape brackets for unzip glob interpretation
    local escaped = inner_path:gsub("%[", "\\["):gsub("%]", "\\]")
    local cmd = string.format('unzip -p "%s" "%s" 2>/dev/null', docx_path, escaped)
    local handle = io.popen(cmd)
    if not handle then return nil end
    local content = handle:read("*a")
    handle:close()
    if content == "" then return nil end
    return content
end

---Build a set from an array for O(1) lookups.
---@param arr table Array of strings
---@return table Set with string keys mapped to true
local function to_set(arr)
    local set = {}
    for _, v in ipairs(arr) do
        set[v] = true
    end
    return set
end

-- ============================================================================
-- Strict XML checks
-- ============================================================================

---Check for unescaped ampersands in XML content.
---Valid entity references: &amp; &lt; &gt; &quot; &apos; &#NNN; &#xHHH;
---Invalid: bare & not starting a valid entity reference.
---@param content string XML content to check
---@return string|nil error First unescaped & context or nil if clean
local function find_unescaped_ampersand(content)
    local pos = 1
    while true do
        local amp = content:find("&", pos, true)
        if not amp then break end
        local after = content:sub(amp + 1)
        -- Check for valid entity reference patterns
        if not after:match("^amp;")
        and not after:match("^lt;")
        and not after:match("^gt;")
        and not after:match("^quot;")
        and not after:match("^apos;")
        and not after:match("^#%d+;")
        and not after:match("^#x%x+;") then
            -- Extract context around the offending &
            local start = math.max(1, amp - 15)
            local context = content:sub(start, amp + 20):gsub("[\r\n]", " ")
            return string.format("unescaped '&' near: ...%s...", context)
        end
        pos = amp + 1
    end
    return nil
end

---Check for unescaped less-than signs in XML text content.
---A bare < inside text (not starting a tag or CDATA) indicates corruption.
---@param content string XML content to check
---@return string|nil error First unescaped < context or nil if clean
local function find_unescaped_lessthan(content)
    -- Strip CDATA sections first (< is valid inside CDATA)
    local stripped = content:gsub("<!%[CDATA%[.-%]%]>", "")
    -- Find < that isn't starting a tag, PI, or comment
    for match_start in stripped:gmatch("()(<[^?!/a-zA-Z])") do
        local context = stripped:sub(math.max(1, match_start - 15), match_start + 20):gsub("[\r\n]", " ")
        return string.format("unescaped '<' near: ...%s...", context)
    end
    return nil
end

-- ============================================================================
-- Validation checks
-- ============================================================================

---Validate well-formedness of all XML files in a DOCX archive.
---Combines SLAXML DOM parsing (catches structural errors like unclosed tags)
---with strict text-level checks (catches unescaped & and < that SLAXML tolerates).
---@param docx_path string Path to DOCX file
---@return boolean pass True if all XML is well-formed
---@return table errors Array of error descriptions
function M.validate_wellformedness(docx_path)
    local files = list_archive_files(docx_path)
    local errors = {}

    for _, path in ipairs(files) do
        if path:match("%.xml$") or path:match("%.rels$") then
            local content = extract(docx_path, path)
            if content then
                -- SLAXML parse (catches structural issues)
                local ok, err = pcall(xml.parse, content)
                if not ok then
                    table.insert(errors, path .. ": " .. tostring(err))
                end

                -- Strict: unescaped ampersand check
                local amp_err = find_unescaped_ampersand(content)
                if amp_err then
                    table.insert(errors, path .. ": " .. amp_err)
                end

                -- Strict: unescaped less-than check
                local lt_err = find_unescaped_lessthan(content)
                if lt_err then
                    table.insert(errors, path .. ": " .. lt_err)
                end
            end
        end
    end

    return #errors == 0, errors
end

---Validate that required OOXML parts exist in the archive.
---@param docx_path string Path to DOCX file
---@return boolean pass True if all required parts exist
---@return table errors Array of error descriptions
function M.validate_required_parts(docx_path)
    local files_set = to_set(list_archive_files(docx_path))

    local required = {
        "[Content_Types].xml",
        "_rels/.rels",
        "word/document.xml",
        "word/_rels/document.xml.rels",
    }

    local errors = {}
    for _, part in ipairs(required) do
        if not files_set[part] then
            table.insert(errors, "Missing required part: " .. part)
        end
    end

    return #errors == 0, errors
end

---Validate relationship consistency.
---Checks that every r:id reference in document.xml has a corresponding entry
---in word/_rels/document.xml.rels, and that internal relationship targets
---exist in the archive.
---@param docx_path string Path to DOCX file
---@return boolean pass True if relationships are consistent
---@return table errors Array of error descriptions
function M.validate_relationships(docx_path)
    local errors = {}
    local files_set = to_set(list_archive_files(docx_path))

    -- Parse document.xml.rels
    local rels_content = extract(docx_path, "word/_rels/document.xml.rels")
    if not rels_content then
        return false, {"Missing word/_rels/document.xml.rels"}
    end

    local ok_parse, rels_doc = pcall(xml.parse, rels_content)
    if not ok_parse then
        return false, {"Malformed word/_rels/document.xml.rels: " .. tostring(rels_doc)}
    end

    -- Build relationship map: id -> {target, external}
    local rels = {}
    for _, el in ipairs(xml.find_by_name(rels_doc, "Relationship")) do
        local id = xml.get_attr(el, "Id")
        local target = xml.get_attr(el, "Target")
        local target_mode = xml.get_attr(el, "TargetMode")
        if id then
            rels[id] = {
                target = target,
                external = (target_mode == "External")
            }
        end
    end

    -- Parse document.xml and find all r:id references
    local doc_content = extract(docx_path, "word/document.xml")
    if not doc_content then
        return false, {"Missing word/document.xml"}
    end

    -- Collect all r:id references (also r:embed, r:link patterns)
    local referenced_ids = {}
    for rid in doc_content:gmatch('r:id="([^"]+)"') do
        referenced_ids[rid] = true
    end
    for rid in doc_content:gmatch('r:embed="([^"]+)"') do
        referenced_ids[rid] = true
    end
    for rid in doc_content:gmatch('r:link="([^"]+)"') do
        referenced_ids[rid] = true
    end

    -- Check all referenced ids exist in rels
    for rid in pairs(referenced_ids) do
        if not rels[rid] then
            table.insert(errors, "Unresolved relationship in document.xml: " .. rid)
        end
    end

    -- Check internal relationship targets exist in archive
    for id, rel in pairs(rels) do
        if not rel.external and rel.target then
            local resolved
            if rel.target:match("^%.%./") then
                -- Relative to parent: "../customXml/item1.xml" -> "customXml/item1.xml"
                resolved = rel.target:gsub("^%.%./", "")
            else
                -- Relative to word/: "document.xml" -> "word/document.xml"
                resolved = "word/" .. rel.target
            end
            if not files_set[resolved] then
                table.insert(errors, "Relationship " .. id .. " target not found: "
                    .. rel.target .. " (resolved: " .. resolved .. ")")
            end
        end
    end

    -- Also validate header/footer .rels if they exist
    for _, path in ipairs(list_archive_files(docx_path)) do
        if path:match("^word/_rels/header%d+%.xml%.rels$")
        or path:match("^word/_rels/footer%d+%.xml%.rels$") then
            local part_rels = extract(docx_path, path)
            if part_rels then
                local ok2, rdoc = pcall(xml.parse, part_rels)
                if ok2 then
                    for _, el in ipairs(xml.find_by_name(rdoc, "Relationship")) do
                        local target = xml.get_attr(el, "Target")
                        local mode = xml.get_attr(el, "TargetMode")
                        local rid = xml.get_attr(el, "Id")
                        if target and not (mode == "External") then
                            local resolved = "word/" .. target
                            if not files_set[resolved] then
                                table.insert(errors, path .. ": relationship " .. (rid or "?")
                                    .. " target not found: " .. target)
                            end
                        end
                    end
                end
            end
        end
    end

    return #errors == 0, errors
end

---Validate content type coverage.
---Checks that every file in the archive has a content type defined in
---[Content_Types].xml, either via Default extension or Override part name.
---@param docx_path string Path to DOCX file
---@return boolean pass True if all parts have content types
---@return table errors Array of error descriptions
function M.validate_content_types(docx_path)
    local ct_content = extract(docx_path, "[Content_Types].xml")
    if not ct_content then
        return false, {"Missing [Content_Types].xml"}
    end

    local ok_parse, ct_doc = pcall(xml.parse, ct_content)
    if not ok_parse then
        return false, {"Malformed [Content_Types].xml: " .. tostring(ct_doc)}
    end

    -- Collect extension defaults
    local defaults = {}
    for _, el in ipairs(xml.find_by_name(ct_doc, "Default")) do
        local ext = xml.get_attr(el, "Extension")
        if ext then
            defaults[ext:lower()] = true
        end
    end

    -- Collect overrides (normalize leading slash)
    local overrides = {}
    for _, el in ipairs(xml.find_by_name(ct_doc, "Override")) do
        local part = xml.get_attr(el, "PartName")
        if part then
            overrides[part:gsub("^/", "")] = true
        end
    end

    -- Check all archive files have a content type
    local errors = {}
    local files = list_archive_files(docx_path)
    for _, path in ipairs(files) do
        -- Skip directories
        if path:match("/$") then goto continue end
        -- [Content_Types].xml itself is implicit
        if path == "[Content_Types].xml" then goto continue end

        local ext = path:match("%.([^.]+)$")
        local has_default = ext and defaults[ext:lower()]
        local has_override = overrides[path] or overrides["/" .. path]

        if not has_default and not has_override then
            table.insert(errors, "No content type for: " .. path)
        end
        ::continue::
    end

    return #errors == 0, errors
end

---Validate namespace declarations on key OOXML parts.
---Checks that root elements of document.xml, headers, and footers declare
---the required WordprocessingML namespace.
---@param docx_path string Path to DOCX file
---@return boolean pass True if all required namespaces are declared
---@return table errors Array of error descriptions
function M.validate_namespaces(docx_path)
    local errors = {}
    local wml_ns = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    -- Parts that must declare the WordprocessingML namespace
    local parts_to_check = {"word/document.xml"}

    -- Discover headers and footers
    for _, path in ipairs(list_archive_files(docx_path)) do
        if path:match("^word/header%d+%.xml$")
        or path:match("^word/footer%d+%.xml$") then
            table.insert(parts_to_check, path)
        end
    end

    for _, part in ipairs(parts_to_check) do
        local content = extract(docx_path, part)
        if content then
            -- Check for WML namespace declaration in root element
            if not content:find(wml_ns, 1, true) then
                table.insert(errors, part .. ": missing WordprocessingML namespace ("
                    .. wml_ns .. ")")
            end
        end
    end

    return #errors == 0, errors
end

-- ============================================================================
-- Composite validation
-- ============================================================================

---Run all validation checks on a DOCX file.
---@param docx_path string Path to DOCX file
---@return boolean pass True if all checks pass
---@return table errors Array of prefixed error descriptions
function M.validate_docx(docx_path)
    -- Verify file exists
    local f = io.open(docx_path, "r")
    if not f then
        return false, {"File not found: " .. docx_path}
    end
    f:close()

    local all_errors = {}
    local all_pass = true

    local checks = {
        {"wellformedness",  M.validate_wellformedness},
        {"required_parts",  M.validate_required_parts},
        {"relationships",   M.validate_relationships},
        {"content_types",   M.validate_content_types},
        {"namespaces",      M.validate_namespaces},
    }

    for _, check in ipairs(checks) do
        local name, fn = check[1], check[2]
        local ok, errs = fn(docx_path)
        if not ok then
            all_pass = false
            for _, e in ipairs(errs) do
                table.insert(all_errors, "[" .. name .. "] " .. e)
            end
        end
    end

    return all_pass, all_errors
end

return M
