--[[
  zip_utils.lua - Cross-platform ZIP utilities using lua-zip (brimworks)

  Purpose: Provide a clean API for ZIP operations using the bundled lua-zip
  library instead of shelling out to system zip/unzip commands.

  Benefits:
  - Cross-platform (Windows, macOS, Linux)
  - No shell injection risks
  - Proper Lua error handling
  - Easier to test

  Usage:
    local zip_utils = require("infra.format.zip_utils")

    -- Extract archive to directory
    zip_utils.extract("/path/to/archive.zip", "/path/to/dest")

    -- Create archive from directory
    zip_utils.create("/path/to/source", "/path/to/output.zip")

  Dependencies:
  - brimworks.zip (lua-zip) - installed via build.sh
  - luv - for directory traversal (bundled)

  @module zip_utils
]]

local M = {}

-- Load lua-zip library
local zip = require("brimworks.zip")

-- Load luv for filesystem operations
local uv = require("luv")

-- ============================================================================
-- Internal Utilities
-- ============================================================================

--- Check if path is a directory
-- @param path string - Path to check
-- @return boolean
local function is_directory(path)
  local stat = uv.fs_stat(path)
  return stat and stat.type == "directory"
end

--- Check if path exists
-- @param path string - Path to check
-- @return boolean
local function path_exists(path)
  return uv.fs_stat(path) ~= nil
end

--- Create directory recursively
-- @param path string - Directory path to create
-- @return boolean success
-- @return string|nil error
local function mkdir_p(path)
  if not path or path == "" then
    return true
  end

  if is_directory(path) then
    return true
  end

  -- Build path incrementally
  local parts = {}
  local start_idx = 1

  -- Handle absolute paths
  if path:sub(1, 1) == "/" then
    start_idx = 2
  end

  for part in path:sub(start_idx):gmatch("[^/]+") do
    table.insert(parts, part)
    local partial = (path:sub(1, 1) == "/" and "/" or "") .. table.concat(parts, "/")

    if not is_directory(partial) and not path_exists(partial) then
      local ok, err = uv.fs_mkdir(partial, 493)  -- 0755 octal
      if not ok and err ~= "EEXIST" then
        return false, "Failed to create directory: " .. partial .. " (" .. tostring(err) .. ")"
      end
    end
  end

  return true
end

--- Recursively delete directory
-- @param path string - Directory path to delete
-- @return boolean success
-- @return string|nil error
local function rmdir_r(path)
  if not path_exists(path) then
    return true
  end

  if not is_directory(path) then
    local ok, err = os.remove(path)
    return ok ~= nil, err
  end

  -- Scan and delete contents
  local req = uv.fs_scandir(path)
  if req then
    while true do
      local name, entry_type = uv.fs_scandir_next(req)
      if not name then break end

      local full_path = path .. "/" .. name
      local ok, err

      if entry_type == "directory" then
        ok, err = rmdir_r(full_path)
      else
        ok, err = os.remove(full_path)
        ok = ok ~= nil
      end

      if not ok then
        return false, err
      end
    end
  end

  -- Remove the now-empty directory
  local ok, err = uv.fs_rmdir(path)
  return ok ~= nil, err
end

--- Recursively collect all files in directory
-- @param dir string - Directory to scan
-- @param prefix string - Prefix for archive paths
-- @param results table - Accumulator for results
-- @return table - Array of {full_path, archive_name, is_dir}
local function collect_files(dir, prefix, results)
  results = results or {}
  prefix = prefix or ""

  local req = uv.fs_scandir(dir)
  if not req then
    return results
  end

  while true do
    local name, entry_type = uv.fs_scandir_next(req)
    if not name then break end

    local full_path = dir .. "/" .. name
    local arc_name = prefix == "" and name or (prefix .. "/" .. name)

    if entry_type == "directory" then
      -- Add directory entry
      table.insert(results, {
        full_path = full_path,
        archive_name = arc_name .. "/",
        is_dir = true
      })
      -- Recurse into subdirectory
      collect_files(full_path, arc_name, results)
    else
      -- Add file entry
      table.insert(results, {
        full_path = full_path,
        archive_name = arc_name,
        is_dir = false
      })
    end
  end

  return results
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Extract ZIP archive to directory
-- @param archive_path string - Path to ZIP file
-- @param dest_dir string - Destination directory
-- @return boolean success
-- @return string|nil error message
function M.extract(archive_path, dest_dir)
  -- Validate inputs
  if not archive_path or archive_path == "" then
    return false, "Archive path is required"
  end

  if not dest_dir or dest_dir == "" then
    return false, "Destination directory is required"
  end

  -- Check archive exists
  if not path_exists(archive_path) then
    return false, "Archive does not exist: " .. archive_path
  end

  -- Create destination directory
  local ok, err = mkdir_p(dest_dir)
  if not ok then
    return false, "Failed to create destination: " .. tostring(err)
  end

  -- Open archive
  local ar, open_err = zip.open(archive_path)
  if not ar then
    return false, "Failed to open archive: " .. tostring(open_err)
  end

  -- Extract each file
  local num_files = ar:get_num_files()
  for i = 1, num_files do
    local stat = ar:stat(i)
    if stat then
      local name = stat.name
      local full_path = dest_dir .. "/" .. name

      if name:sub(-1) == "/" then
        -- Directory entry
        local dir_ok, dir_err = mkdir_p(full_path)
        if not dir_ok then
          ar:close()
          return false, "Failed to create directory: " .. tostring(dir_err)
        end
      else
        -- File entry - ensure parent directory exists
        local parent = full_path:match("(.+)/[^/]+$")
        if parent then
          local parent_ok, parent_err = mkdir_p(parent)
          if not parent_ok then
            ar:close()
            return false, "Failed to create parent directory: " .. tostring(parent_err)
          end
        end

        -- Read and write file content
        local file_handle = ar:open(i)
        if file_handle then
          local content = file_handle:read(stat.size)
          file_handle:close()

          if content then
            local f = io.open(full_path, "wb")
            if f then
              f:write(content)
              f:close()
            else
              ar:close()
              return false, "Failed to write file: " .. full_path
            end
          end
        end
      end
    end
  end

  ar:close()
  return true
end

--- Create ZIP archive from directory
-- @param source_dir string - Source directory to archive
-- @param archive_path string - Output archive path
-- @return boolean success
-- @return string|nil error message
function M.create(source_dir, archive_path)
  -- Validate inputs
  if not source_dir or source_dir == "" then
    return false, "Source directory is required"
  end

  if not archive_path or archive_path == "" then
    return false, "Archive path is required"
  end

  -- Check source exists
  if not is_directory(source_dir) then
    return false, "Source is not a directory: " .. source_dir
  end

  -- Remove existing archive
  if path_exists(archive_path) then
    os.remove(archive_path)
  end

  -- Collect all files to add
  local files = collect_files(source_dir, "")

  -- Create archive
  local ar, open_err = zip.open(archive_path, zip.CREATE)
  if not ar then
    return false, "Failed to create archive: " .. tostring(open_err)
  end

  -- Add each file
  for _, entry in ipairs(files) do
    if entry.is_dir then
      -- Add directory entry
      local ok, add_err = pcall(function()
        ar:add_dir(entry.archive_name)
      end)
      if not ok then
        ar:close()
        return false, "Failed to add directory: " .. entry.archive_name .. " (" .. tostring(add_err) .. ")"
      end
    else
      -- Read file content
      local f = io.open(entry.full_path, "rb")
      if f then
        local content = f:read("*a")
        f:close()

        -- Add to archive
        local ok, add_err = pcall(function()
          ar:add(entry.archive_name, "string", content)
        end)
        if not ok then
          ar:close()
          return false, "Failed to add file: " .. entry.archive_name .. " (" .. tostring(add_err) .. ")"
        end
      else
        ar:close()
        return false, "Failed to read file: " .. entry.full_path
      end
    end
  end

  -- Close and commit
  local close_ok, close_err = pcall(function()
    ar:close()
  end)

  if not close_ok then
    return false, "Failed to finalize archive: " .. tostring(close_err)
  end

  return true
end

--- Get current working directory using luv
-- @return string cwd
function M.cwd()
  return uv.cwd()
end

--- Delete directory recursively
-- Exposed for cleanup after extract operations
-- @param path string - Directory to delete
-- @return boolean success
-- @return string|nil error
M.rmdir_r = rmdir_r

--- Create directory recursively
-- @param path string - Directory to create
-- @return boolean success
-- @return string|nil error
M.mkdir_p = mkdir_p

--- Check if path exists
-- @param path string - Path to check
-- @return boolean
M.path_exists = path_exists

--- Check if path is a directory
-- @param path string - Path to check
-- @return boolean
M.is_directory = is_directory

return M
