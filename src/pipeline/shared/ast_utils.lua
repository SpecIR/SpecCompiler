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

---Decode AST JSON string to Pandoc blocks.
---Canonical implementation: handles full Pandoc documents, block arrays,
---and single blocks. Returns empty table for empty/nil input.
---@param ast_json string|nil JSON-encoded AST
---@return table blocks Array of Pandoc blocks (empty table on failure)
function M.decode_blocks(ast_json)
    if not ast_json or ast_json == "" or ast_json == "[]" then
        return {}
    end

    local result = pandoc.json.decode(ast_json)
    if not result then return {} end

    return M.extract_blocks(result) or {}
end

---Decode AST JSON and discriminate between blocks and inlines.
---Used by attribute renderers that need to know whether the content
---is block-level (Para, Plain, BulletList) or inline-level (Str, Link, etc.).
---@param ast_json string|nil JSON-encoded AST
---@return table|nil content Decoded content, or nil
---@return string|nil kind "blocks" or "inlines", or nil
function M.decode_with_type(ast_json)
    if not ast_json or ast_json == "" then return nil, nil end

    local result = pandoc.json.decode(ast_json)
    if result and type(result) == "table" and #result > 0 then
        local first = result[1]
        if first and first.t and (first.t == "Para" or first.t == "Plain" or first.t == "BulletList") then
            return result, "blocks"
        else
            return result, "inlines"
        end
    end
    return nil, nil
end

return M
