---File Walker for SpecCompiler.
---Provides robust file reading and path resolution.

local uv = require("luv")

local M = {}

---Read a file from the filesystem.
---@param path string
---@return string|nil content
---@return string|nil error
function M.read_file(path)
    local f = io.open(path, "r")
    if not f then
        return nil, "Could not open file: " .. path
    end
    local content = f:read("*all")
    f:close()
    return content
end

---Resolve a path relative to a base directory.
---@param path string
---@param base_dir string
---@return string
function M.resolve_path(path, base_dir)
    if path:match("^/") then return path end -- Absolute
    if not base_dir then return path end
    
    -- Strip trailing slash from base if present
    base_dir = base_dir:gsub("/$", "")
    return base_dir .. "/" .. path
end

---Recursively find files matching a pattern.
---@param dir string Directory to search
---@param pattern string Lua pattern to match filenames (e.g., "%.yaml$")
---@return table files Array of matching file paths
function M.glob(dir, pattern)
    local results = {}

    local function scan(path)
        local req, err = uv.fs_scandir(path)
        if not req then return end

        while true do
            local name, entry_type = uv.fs_scandir_next(req)
            if not name then break end

            local full_path = path .. "/" .. name

            if entry_type == "directory" then
                scan(full_path)
            elseif entry_type == "file" and name:match(pattern) then
                table.insert(results, full_path)
            end
        end
    end

    scan(dir)
    table.sort(results)
    return results
end

return M
