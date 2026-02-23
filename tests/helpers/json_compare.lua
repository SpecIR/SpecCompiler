-- JSON comparison helper for E2E tests
-- Provides semantic comparison of JSON structures

local M = {}

-- Deep comparison of two values
local function deep_equal(a, b, path)
    path = path or ""

    if type(a) ~= type(b) then
        return false, string.format("Type mismatch at %s: %s vs %s",
            path, type(a), type(b))
    end

    if type(a) ~= "table" then
        if a ~= b then
            return false, string.format("Value mismatch at %s: %s vs %s",
                path, tostring(a), tostring(b))
        end
        return true
    end

    -- Compare tables
    local checked = {}

    for k, v in pairs(a) do
        checked[k] = true
        local new_path = path .. "." .. tostring(k)
        local ok, err = deep_equal(v, b[k], new_path)
        if not ok then
            return false, err
        end
    end

    for k, v in pairs(b) do
        if not checked[k] then
            return false, string.format("Extra key at %s.%s", path, tostring(k))
        end
    end

    return true
end

-- Parse JSON string to Lua table
local function parse_json(str)
    return pandoc.json.decode(str)
end

--- Compare two JSON strings
---@param actual string JSON string
---@param expected string JSON string
---@return boolean success
---@return string|nil error_message
function M.compare(actual, expected)
    local actual_tbl, err1 = parse_json(actual)
    if not actual_tbl then
        return false, "Failed to parse actual JSON: " .. (err1 or "unknown")
    end

    local expected_tbl, err2 = parse_json(expected)
    if not expected_tbl then
        return false, "Failed to parse expected JSON: " .. (err2 or "unknown")
    end

    return deep_equal(actual_tbl, expected_tbl, "root")
end

--- Compare two JSON files
---@param actual_path string Path to actual JSON file
---@param expected_path string Path to expected JSON file
---@return boolean success
---@return string|nil error_message
function M.compare_files(actual_path, expected_path)
    local actual_f = io.open(actual_path, "r")
    if not actual_f then
        return false, "Cannot open actual file: " .. actual_path
    end
    local actual = actual_f:read("*a")
    actual_f:close()

    local expected_f = io.open(expected_path, "r")
    if not expected_f then
        return false, "Cannot open expected file: " .. expected_path
    end
    local expected = expected_f:read("*a")
    expected_f:close()

    return M.compare(actual, expected)
end

--- Generate a diff report between two JSON structures
---@param actual string JSON string
---@param expected string JSON string
---@return string diff Human-readable diff
function M.diff(actual, expected)
    local actual_tbl = parse_json(actual)
    local expected_tbl = parse_json(expected)

    if not actual_tbl or not expected_tbl then
        return "Cannot generate diff: JSON parsing failed"
    end

    local ok, err = deep_equal(actual_tbl, expected_tbl, "root")
    if ok then
        return "No differences"
    end

    return err or "Unknown difference"
end

return M
