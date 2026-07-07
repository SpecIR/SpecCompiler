-- src/infra/hash_utils.lua
local M = {}

-- Lazy-load pure Lua SHA library (only when pandoc.sha1 unavailable)
local sha2_lib = nil

---Compute SHA1 hash of content
---@param content string Content to hash
---@return string hash 40-character hex string
function M.sha1(content)
    -- Use pandoc's sha1 if available (fastest path when running inside Pandoc)
    if pandoc and pandoc.sha1 then
        return pandoc.sha1(content)
    end

    -- Fallback: use pure Lua SHA1 implementation (for standalone workers)
    if not sha2_lib then
        sha2_lib = require("sha2")
    end
    return sha2_lib.sha1(content)
end

---Compute SHA1 of a file
---@param path string File path
---@return string|nil hash, string|nil error
function M.sha1_file(path)
    local uv = require("luv")
    local stat = uv.fs_stat(path)
    if not stat then
        return nil, "File not found: " .. path
    end

    local fd = uv.fs_open(path, "r", 420)
    if not fd then
        return nil, "Cannot open file: " .. path
    end

    local content = uv.fs_read(fd, stat.size)
    uv.fs_close(fd)

    if not content then
        return nil, "Cannot read file: " .. path
    end

    return M.sha1(content)
end

return M
