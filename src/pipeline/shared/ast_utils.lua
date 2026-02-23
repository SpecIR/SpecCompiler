---AST utilities for SpecCompiler.
---Shared helpers for working with decoded Pandoc AST JSON.
---
---@module ast_utils
local M = {}

---Extract blocks from a decoded AST.
---Handles the three forms that pandoc.json.decode can produce:
---  1. Full Pandoc document JSON (has "pandoc-api-version" or "blocks" key)
---  2. Single block element (has "t" key)
---  3. Array of blocks (plain table)
---Returns nil if decoded is nil.
---@param decoded table|nil Decoded AST JSON
---@return table|nil blocks Array of block elements, or nil
function M.extract_blocks(decoded)
    if not decoded then return nil end

    if decoded["pandoc-api-version"] or decoded.blocks then
        -- Full Pandoc document JSON - extract blocks
        return decoded.blocks or {}
    elseif decoded.t then
        -- Single block element
        return { decoded }
    else
        -- Array of blocks
        return decoded
    end
end

return M
