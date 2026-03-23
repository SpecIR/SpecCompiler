---Lua source mutation operators for mutation testing.
---Each operator works on a single line, generating one mutation per match site.
---
---An operator's apply() receives (line_text, line_number) and returns
---an array of {line=string, desc=string} — one per mutation site.
---@module lua_operators

local M = {}

---Apply a pattern-based substitution at each occurrence site independently on a line.
---@param line string The source line
---@param pattern string Lua pattern to match
---@param replacement string|function Replacement text
---@param desc_fmt string Format string (receives original, replacement)
---@return table[] Array of {line=string, desc=string}
local function each_site_on_line(line, pattern, replacement, desc_fmt)
    local mutations = {}
    local search_start = 1

    while true do
        local s, e, capture = line:find(pattern, search_start)
        if not s then break end

        local original_text = capture or line:sub(s, e)
        local replaced
        if type(replacement) == "function" then
            replaced = replacement(original_text)
        else
            replaced = replacement
        end

        if replaced ~= original_text then
            local mutated = line:sub(1, s - 1) .. replaced .. line:sub(e + 1)
            local desc = string.format(desc_fmt, original_text, replaced)
            table.insert(mutations, { line = mutated, desc = desc })
        end

        search_start = e + 1
    end

    return mutations
end

---Check if a position in a line is inside a string literal or comment.
---Simple heuristic: count unescaped quotes before position.
---@param line string
---@param pos number
---@return boolean
local function in_string_or_comment(line, pos)
    -- Check for line comment
    local comment_start = line:find("%-%-")
    if comment_start and pos >= comment_start then
        return true
    end

    -- Simple quote counting (doesn't handle [[ ]] long strings perfectly)
    local in_dq = false
    local in_sq = false
    for i = 1, pos - 1 do
        local c = line:sub(i, i)
        local prev = i > 1 and line:sub(i - 1, i - 1) or ""
        if c == '"' and prev ~= "\\" and not in_sq then
            in_dq = not in_dq
        elseif c == "'" and prev ~= "\\" and not in_dq then
            in_sq = not in_sq
        end
    end
    return in_dq or in_sq
end

-- ============================================================================
-- Operator definitions
-- ============================================================================

M.operators = {}

--- 1. Flip equality: == ↔ ~=
table.insert(M.operators, {
    name = "flip_eq",
    description = "== ↔ ~=",
    apply = function(line)
        local mutations = {}
        -- == → ~=
        for _, m in ipairs(each_site_on_line(line, "(==)", "~=", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- ~= → ==
        for _, m in ipairs(each_site_on_line(line, "(~=)", "==", "%s → %s")) do
            table.insert(mutations, m)
        end
        return mutations
    end
})

--- 2. Flip ordering: < ↔ <=, > ↔ >=
table.insert(M.operators, {
    name = "flip_order",
    description = "< ↔ <=, > ↔ >=",
    apply = function(line)
        local mutations = {}
        -- >= → > (tighten)
        for _, m in ipairs(each_site_on_line(line, "(>=)", ">", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- <= → < (tighten)
        for _, m in ipairs(each_site_on_line(line, "(<=)", "<", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- Standalone > → >= (need to avoid >= and >> and ->)
        local search_start = 1
        while true do
            local s, e = line:find(">", search_start, true)
            if not s then break end
            local next_c = line:sub(e + 1, e + 1)
            local prev_c = line:sub(s - 1, s - 1)
            if next_c ~= "=" and prev_c ~= "-" and prev_c ~= ">" and
               not in_string_or_comment(line, s) then
                table.insert(mutations, {
                    line = line:sub(1, s - 1) .. ">=" .. line:sub(e + 1),
                    desc = "> → >="
                })
            end
            search_start = e + 1
        end
        -- Standalone < → <=
        search_start = 1
        while true do
            local s, e = line:find("<", search_start, true)
            if not s then break end
            local next_c = line:sub(e + 1, e + 1)
            if next_c ~= "=" and next_c ~= "<" and
               not in_string_or_comment(line, s) then
                table.insert(mutations, {
                    line = line:sub(1, s - 1) .. "<=" .. line:sub(e + 1),
                    desc = "< → <="
                })
            end
            search_start = e + 1
        end
        return mutations
    end
})

--- 3. Flip logical: and ↔ or
table.insert(M.operators, {
    name = "flip_logic",
    description = "and ↔ or",
    apply = function(line)
        local mutations = {}
        for _, m in ipairs(each_site_on_line(line, "%f[%w](and)%f[%W]", "or", "%s → %s")) do
            table.insert(mutations, m)
        end
        for _, m in ipairs(each_site_on_line(line, "%f[%w](or)%f[%W]", "and", "%s → %s")) do
            table.insert(mutations, m)
        end
        return mutations
    end
})

--- 4. Remove not
table.insert(M.operators, {
    name = "remove_not",
    description = "not x → x",
    apply = function(line)
        return each_site_on_line(line, "(not )(%w)", function() return "" end,
            "removed: %s → %s")
    end
})

--- 5. Flip boolean literals: true ↔ false
table.insert(M.operators, {
    name = "flip_bool",
    description = "true ↔ false",
    apply = function(line)
        local mutations = {}
        for _, m in ipairs(each_site_on_line(line, "%f[%w](true)%f[%W]", "false", "%s → %s")) do
            table.insert(mutations, m)
        end
        for _, m in ipairs(each_site_on_line(line, "%f[%w](false)%f[%W]", "true", "%s → %s")) do
            table.insert(mutations, m)
        end
        return mutations
    end
})

--- 6. nil → false
table.insert(M.operators, {
    name = "nil_to_false",
    description = "nil → false",
    apply = function(line)
        -- Only mutate nil when it's a value, not in type annotations or comments
        if line:match("^%s*%-%-") then return {} end
        return each_site_on_line(line, "%f[%w](nil)%f[%W]", "false", "%s → %s")
    end
})

--- 7. Flip return boolean: return true ↔ return false
table.insert(M.operators, {
    name = "flip_return",
    description = "return true ↔ return false",
    apply = function(line)
        local mutations = {}
        if line:match("return true") then
            table.insert(mutations, {
                line = line:gsub("return true", "return false", 1),
                desc = "return true → return false"
            })
        end
        if line:match("return false") then
            table.insert(mutations, {
                line = line:gsub("return false", "return true", 1),
                desc = "return false → return true"
            })
        end
        return mutations
    end
})

--- 8. Off-by-one: + 1 → + 0, - 1 → - 0
table.insert(M.operators, {
    name = "off_by_one",
    description = "+/- 1 → +/- 0",
    apply = function(line)
        local mutations = {}
        -- + 1 → + 0
        for _, m in ipairs(each_site_on_line(line, "(%+ 1)%f[%D]", "+ 0", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- - 1 → - 0
        for _, m in ipairs(each_site_on_line(line, "(%-% 1)%f[%D]", "- 0", "%s → %s")) do
            table.insert(mutations, m)
        end
        return mutations
    end
})

--- 9. Boundary shift: > 0 → >= 0, < 0 → <= 0
table.insert(M.operators, {
    name = "boundary",
    description = "> 0 → >= 0",
    apply = function(line)
        local mutations = {}
        if line:match("> 0%f[%D]") and not line:match(">= 0") then
            table.insert(mutations, {
                line = line:gsub("> 0(%f[%D])", ">= 0%1", 1),
                desc = "> 0 → >= 0"
            })
        end
        if line:match("< 0%f[%D]") and not line:match("<= 0") then
            table.insert(mutations, {
                line = line:gsub("< 0(%f[%D])", "<= 0%1", 1),
                desc = "< 0 → <= 0"
            })
        end
        return mutations
    end
})

--- 10. Empty string mutation: "" → "MUTANT"
table.insert(M.operators, {
    name = "empty_string",
    description = "\"\" → \"MUTANT\"",
    apply = function(line)
        if line:match("^%s*%-%-") then return {} end  -- skip comments
        return each_site_on_line(line, '("")', '"MUTANT"', '%s → %s')
    end
})

---Generate all single-site mutations for a given source line.
---@param line string The source line
---@param line_num number Line number (1-based)
---@return table[] Array of {operator=string, line=string, desc=string, line_num=number}
function M.generate_mutations(line, line_num)
    -- Skip blank lines, comments, and pure-whitespace
    if line:match("^%s*$") or line:match("^%s*%-%-") then
        return {}
    end

    local all = {}
    for _, op in ipairs(M.operators) do
        local mutations = op.apply(line)
        for _, m in ipairs(mutations) do
            table.insert(all, {
                operator = op.name,
                line = m.line,
                desc = m.desc,
                line_num = line_num
            })
        end
    end
    return all
end

return M
