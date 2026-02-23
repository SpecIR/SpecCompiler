---Shared include expansion helpers.
---@module include_utils

local M = {}

---Check if a block is an include directive.
---@param block table Pandoc block
---@return boolean
function M.is_include_block(block)
    if not block or block.t ~= "CodeBlock" then return false end
    if not block.classes then return false end
    for _, class in ipairs(block.classes) do
        if class == "include" then
            return true
        end
    end
    return false
end

---Parse include paths from a code block payload.
---@param text string
---@return table paths
function M.iter_include_paths(text)
    local paths = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        local rel_path = line:match("^%s*(.-)%s*$")
        if rel_path ~= "" and not rel_path:match("^#") then
            paths[#paths + 1] = rel_path
        end
    end
    return paths
end

---Resolve a path relative to a base directory.
---@param base_dir string
---@param rel_path string
---@return string
function M.resolve_path(base_dir, rel_path)
    if rel_path:match("^/") then
        return rel_path
    end

    local path = base_dir .. "/" .. rel_path
    path = path:gsub("/+", "/")
    path = path:gsub("/%./", "/")

    while path:match("/[^/]+/%.%./") do
        path = path:gsub("/[^/]+/%.%./", "/")
    end
    path = path:gsub("/[^/]+/%.%.$", "")

    return path
end

---Read file content from disk.
---@param path string
---@return string|nil
---@return string|nil
function M.read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "File not found: " .. path
    end
    local content = f:read("*all")
    f:close()
    return content
end

---Return the parent directory for a path.
---@param path string
---@return string
function M.dirname(path)
    local dir = path:match("(.+)/[^/]*$")
    return dir or "."
end

---Annotate blocks with original source file metadata for diagnostics.
---@param blocks table
---@param source_file string
function M.annotate_source_file(blocks, source_file)
    for _, block in ipairs(blocks or {}) do
        if block.attr then
            block.attr.attributes = block.attr.attributes or {}
            block.attr.attributes["data-source-file"] = source_file
        elseif block.attributes then
            block.attributes["data-source-file"] = source_file
        end
    end
end

return M
