-- DOCX test utilities
-- Helpers for validating DOCX output in tests

local M = {}

---Read a DOCX (ZIP) archive with pandoc's built-in zip module.
---@param docx_path string Path to DOCX file
---@return table|nil archive pandoc.zip.Archive, or nil if unreadable
function M.open_archive(docx_path)
    local f = io.open(docx_path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    local ok, archive = pcall(pandoc.zip.Archive, data)
    return ok and archive or nil
end

---Extract a file from a DOCX (ZIP) archive.
---@param docx_path string Path to DOCX file
---@param inner_path string Path within the DOCX (e.g., "word/document.xml")
---@return string|nil content File contents
---@return string|nil error Error message
function M.extract_from_docx(docx_path, inner_path)
    local archive = M.open_archive(docx_path)
    if not archive then
        return nil, "Failed to read archive: " .. docx_path
    end
    for _, entry in ipairs(archive.entries) do
        if entry.path == inner_path then
            local content = entry:contents()
            if content ~= "" then return content end
        end
    end
    return nil, "File not found in archive: " .. inner_path
end

---Check if a DOCX file exists and is valid.
---@param docx_path string Path to DOCX file
---@return boolean valid
---@return string|nil error Error message
function M.is_valid_docx(docx_path)
    -- Check file exists
    local f = io.open(docx_path, "r")
    if not f then
        return false, "File does not exist: " .. docx_path
    end
    f:close()

    -- Check it's a valid ZIP with required DOCX parts
    if not M.extract_from_docx(docx_path, "[Content_Types].xml") then
        return false, "Missing [Content_Types].xml"
    end

    local document = M.extract_from_docx(docx_path, "word/document.xml")
    if not document then
        return false, "Missing word/document.xml"
    end

    return true
end

---Get the document.xml content from a DOCX file.
---@param docx_path string Path to DOCX file
---@return string|nil content XML content
function M.get_document_xml(docx_path)
    return M.extract_from_docx(docx_path, "word/document.xml")
end

---Count occurrences of a pattern in the document.xml.
---@param docx_path string Path to DOCX file
---@param pattern string Lua pattern to search for
---@return number count Number of matches
function M.count_pattern(docx_path, pattern)
    local xml = M.get_document_xml(docx_path)
    if not xml then return 0 end

    local count = 0
    for _ in xml:gmatch(pattern) do
        count = count + 1
    end
    return count
end

---Check if document contains specific text.
---@param docx_path string Path to DOCX file
---@param text string Text to search for
---@return boolean found
function M.contains_text(docx_path, text)
    local xml = M.get_document_xml(docx_path)
    if not xml then return false end
    return xml:find(text, 1, true) ~= nil
end

---Count images in the DOCX (checks relationships).
---@param docx_path string Path to DOCX file
---@return number count Number of images
function M.count_images(docx_path)
    local rels = M.extract_from_docx(docx_path, "word/_rels/document.xml.rels")
    if not rels then return 0 end

    local count = 0
    for _ in rels:gmatch('Type="[^"]*image"') do
        count = count + 1
    end
    return count
end

---Count tables in the document.
---@param docx_path string Path to DOCX file
---@return number count Number of tables
function M.count_tables(docx_path)
    return M.count_pattern(docx_path, "<w:tbl>")
end

---Count math blocks (OMML) in the document.
---@param docx_path string Path to DOCX file
---@return number count Number of math blocks
function M.count_math_blocks(docx_path)
    return M.count_pattern(docx_path, "<m:oMath")
end

---Count headings in the document (paragraphs with Heading styles).
---@param docx_path string Path to DOCX file
---@return number count Number of headings
function M.count_headings(docx_path)
    local xml = M.get_document_xml(docx_path)
    if not xml then return 0 end

    local count = 0
    -- Count Heading1, Heading2, Heading3, etc.
    for _ in xml:gmatch('<w:pStyle w:val="Heading%d+"') do
        count = count + 1
    end
    -- Also count unnumbered headings
    for _ in xml:gmatch('<w:pStyle w:val="UnnumberedHeading"') do
        count = count + 1
    end
    return count
end

---Check if TOC field is present.
---@param docx_path string Path to DOCX file
---@return boolean present
function M.has_toc_field(docx_path)
    return M.count_pattern(docx_path, "TOC") > 0
end

---Check if bookmark exists.
---@param docx_path string Path to DOCX file
---@param bookmark_name string Bookmark name
---@return boolean exists
function M.has_bookmark(docx_path, bookmark_name)
    local xml = M.get_document_xml(docx_path)
    if not xml then return false end
    return xml:find('w:name="' .. bookmark_name .. '"', 1, true) ~= nil
end

---List all files in the DOCX archive.
---@param docx_path string Path to DOCX file
---@return table files Array of file paths
function M.list_files(docx_path)
    local archive = M.open_archive(docx_path)
    if not archive then return {} end

    local files = {}
    for _, entry in ipairs(archive.entries) do
        table.insert(files, entry.path)
    end
    return files
end

return M
