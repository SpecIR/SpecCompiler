-- src/backend/docx/reference_cache.lua
-- Tracks whether reference.docx needs rebuilding by comparing preset SHA1 hashes
local hash_utils = require("infra.hash_utils")

local M = {}

-- Schema for build_meta table
local BUILD_META_SCHEMA = [[
CREATE TABLE IF NOT EXISTS build_meta (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
]]

--- Ensure the build_meta table exists
---@param db table Database handler (from core.db)
local function ensure_schema(db)
    db:exec_sql(BUILD_META_SCHEMA)
end

--- Compute the combined hash of a preset chain (top preset + extended bases).
---@param preset_paths string[] Paths to every preset.lua in the extends chain
---@return string|nil hash Combined hash, or nil if any file is unreadable
local function chain_hash(preset_paths)
    local hashes = {}
    for _, path in ipairs(preset_paths) do
        local hash = hash_utils.sha1_file(path)
        if not hash then
            return nil
        end
        hashes[#hashes + 1] = hash
    end
    return table.concat(hashes, ":")
end

--- Check if reference.docx needs to be rebuilt
---@param db table Database handler (from core.db)
---@param preset_paths string[] Paths to every preset.lua in the extends chain
---@param reference_path string Path to reference.docx
---@return boolean needs_rebuild
function M.needs_rebuild(db, preset_paths, reference_path)
    -- Check if reference.docx exists
    local f = io.open(reference_path, "r")
    if not f then
        return true
    end
    f:close()

    -- Ensure build_meta table exists
    ensure_schema(db)

    -- Compare combined hashes across the whole extends chain
    local current_hash = chain_hash(preset_paths)
    if not current_hash then
        return true  -- Can't compute hash, rebuild to be safe
    end

    -- Query stored hash using db handler methods
    local results = db:query_all(
        "SELECT value FROM build_meta WHERE key = :key",
        { key = "preset_hash" }
    )

    if not results or #results == 0 then
        return true  -- No stored hash, needs rebuild
    end

    local stored_hash = results[1].value
    return current_hash ~= stored_hash
end

--- Update the stored preset hash after rebuild
---@param db table Database handler (from core.db)
---@param preset_paths string[] Paths to every preset.lua in the extends chain
---@return boolean success
---@return string|nil error
function M.update_hash(db, preset_paths)
    local hash = chain_hash(preset_paths)
    if not hash then
        return false, "Cannot compute hash for preset chain"
    end

    -- Ensure build_meta table exists
    ensure_schema(db)

    -- Use db handler's execute with parameterized query
    local success = db:execute(
        "INSERT OR REPLACE INTO build_meta (key, value) VALUES (:key, :value)",
        { key = "preset_hash", value = hash }
    )

    if not success then
        return false, "Failed to store hash in database"
    end

    return true, nil
end

return M
