---Shared utility for building prefix matchers from view/float type declarations.
---Eliminates hardcoded prefix patterns in type modules by deriving matchers
---from the declared `inline_prefix` and `aliases`.
---
---@module prefix_matcher
local M = {}

---Escape Lua pattern special characters in a string.
---@param s string
---@return string
local function escape_pattern(s)
    return s:gsub("([%.%-%+%*%?%^%$%(%)%[%]%%])", "%%%1")
end

---Build a prefix matcher from a type declaration.
---
---The returned function matches text against `prefix: content` patterns
---for the primary `inline_prefix` and all declared `aliases`.
---
---@param decl table Type declaration with `inline_prefix` and optional `aliases`
---@param opts table|nil Options: `require_content` (bool) — if true, content must be non-empty
---@return function matcher function(text) → content|nil, prefix|nil
function M.from_decl(decl, opts)
    opts = opts or {}
    local content_pat = opts.require_content and "(.+)" or "(.*)"

    local entries = {}
    if decl.inline_prefix then entries[#entries + 1] = decl.inline_prefix end
    for _, alias in ipairs(decl.aliases or {}) do
        entries[#entries + 1] = alias
    end

    local patterns = {}
    for _, prefix in ipairs(entries) do
        patterns[#patterns + 1] = {
            prefix = prefix,
            pat = "^" .. escape_pattern(prefix) .. ":%s*" .. content_pat .. "$"
        }
    end

    return function(text)
        if not text then return nil, nil end
        for _, entry in ipairs(patterns) do
            local match = text:match(entry.pat)
            if match then return match, entry.prefix end
        end
        return nil, nil
    end
end

---Build a CodeBlock matcher from a type declaration.
---
---CodeBlocks use a dual-match: either the first CSS class starts with the
---prefix (with optional colon and params), or the block text starts with
---`prefix:`.  Returns (params_string, matched_prefix) or (nil, nil).
---
---@param decl table Type declaration with `inline_prefix` and optional `aliases`
---@return function matcher function(block) → params|nil, prefix|nil
function M.codeblock_from_decl(decl)
    local entries = {}
    if decl.inline_prefix then entries[#entries + 1] = decl.inline_prefix end
    for _, alias in ipairs(decl.aliases or {}) do
        entries[#entries + 1] = alias
    end

    local class_patterns = {}
    local text_patterns = {}
    for _, prefix in ipairs(entries) do
        class_patterns[#class_patterns + 1] = {
            prefix = prefix,
            pat = "^" .. escape_pattern(prefix) .. ":?(.*)$"
        }
        text_patterns[#text_patterns + 1] = {
            prefix = prefix,
            pat = "^" .. escape_pattern(prefix) .. ":%s*(.*)"
        }
    end

    return function(block)
        if not block then return nil, nil end
        local first_class = (block.classes or {})[1] or ""
        local block_text = block.text or ""

        -- Try class match first (e.g., ```lof or ```lof:params)
        for _, entry in ipairs(class_patterns) do
            local rest = first_class:match(entry.pat)
            if rest then return rest, entry.prefix end
        end
        -- Try text match (e.g., block text starts with prefix:)
        for _, entry in ipairs(text_patterns) do
            local rest = block_text:match(entry.pat)
            if rest then return rest, entry.prefix end
        end
        return nil, nil
    end
end

return M
