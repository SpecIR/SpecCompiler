---JSON wrapper module for SpecCompiler.
---Provides unified interface using dkjson (pure Lua).
---Replaces pandoc.json.encode/decode for out-of-Pandoc usage.
---
---@module infra.json
local dkjson = require("dkjson")

local M = {}

---Encode a Lua table to JSON string.
---@param value any Lua value to encode
---@return string|nil json_str JSON string or nil if value is nil
function M.encode(value)
    if value == nil then
        return nil
    end
    local result = dkjson.encode(value)
    return result
end

---Decode a JSON string to Lua table.
---@param str string|nil JSON string to decode
---@return table|nil result Lua table or nil if string is nil/invalid
function M.decode(str)
    if str == nil or str == "" then
        return nil
    end
    local result, _, err = dkjson.decode(str)
    if err then
        return nil
    end
    return result
end

return M
