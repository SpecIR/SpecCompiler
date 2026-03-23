---SQL mutation operators for proof view mutation testing.
---Each operator generates single-site mutations on a SQL string.
---
---An operator returns an array of {mutated_sql, description} pairs,
---one per mutation site found in the input.
---@module sql_operators

local M = {}

---Apply a pattern-based substitution at each occurrence site independently.
---Returns an array of single-site mutations.
---@param sql string Original SQL string
---@param pattern string Lua pattern to match
---@param replacement string|function Replacement string or function
---@param desc_fmt string Format string for description (receives original match)
---@return table[] Array of {sql=string, desc=string}
local function each_site(sql, pattern, replacement, desc_fmt)
    local mutations = {}
    local search_start = 1

    while true do
        local s, e, capture = sql:find(pattern, search_start)
        if not s then break end

        local original_text = capture or sql:sub(s, e)
        local replaced
        if type(replacement) == "function" then
            replaced = replacement(original_text)
        else
            replaced = replacement
        end

        local mutated = sql:sub(1, s - 1) .. replaced .. sql:sub(e + 1)
        local desc = string.format(desc_fmt, original_text, replaced)
        table.insert(mutations, {
            sql = mutated,
            desc = desc,
            position = s
        })

        search_start = e + 1
    end

    return mutations
end

---Check if position `pos` falls inside a SQL single-line comment (-- ...).
---@param sql string
---@param pos number
---@return boolean
local function in_sql_comment(sql, pos)
    -- Walk backward from pos to find the start of the line
    local line_start = pos
    while line_start > 1 and sql:sub(line_start - 1, line_start - 1) ~= "\n" do
        line_start = line_start - 1
    end
    local line_prefix = sql:sub(line_start, pos)
    -- Check if "--" appears before this position on the same line
    local dash_pos = line_prefix:find("%-%-")
    return dash_pos ~= nil and (line_start + dash_pos - 1) < pos
end

-- ============================================================================
-- Operator definitions
-- ============================================================================

M.operators = {}

--- 1. Negate EXISTS: NOT EXISTS → EXISTS (and vice versa)
table.insert(M.operators, {
    name = "negate_exists",
    description = "NOT EXISTS ↔ EXISTS",
    apply = function(sql)
        local mutations = {}
        -- NOT EXISTS → EXISTS (skip DDL "IF NOT EXISTS" and SQL comments)
        local search_start = 1
        while true do
            local s, e = sql:find("NOT EXISTS", search_start, true)
            if not s then break end
            -- Skip DDL preamble: "IF NOT EXISTS"
            local prefix4 = sql:sub(math.max(1, s - 3), s - 1)
            if prefix4 ~= "IF " and not in_sql_comment(sql, s) then
                local mutated = sql:sub(1, s - 1) .. "EXISTS" .. sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = "NOT EXISTS → EXISTS",
                    position = s
                })
            end
            search_start = e + 1
        end
        -- Standalone EXISTS (not preceded by NOT) → NOT EXISTS
        -- Use a negative lookbehind approximation: find EXISTS not preceded by "NOT "
        search_start = 1
        while true do
            local s, e = sql:find("EXISTS", search_start, true)
            if not s then break end
            local prefix = sql:sub(math.max(1, s - 4), s - 1)
            if prefix ~= "NOT " and prefix ~= "T IF " and not in_sql_comment(sql, s) then
                local mutated = sql:sub(1, s - 1) .. "NOT EXISTS" .. sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = "EXISTS → NOT EXISTS",
                    position = s
                })
            end
            search_start = e + 1
        end
        return mutations
    end
})

--- 2. Relax AND: replace one AND with OR at a time
table.insert(M.operators, {
    name = "relax_and",
    description = "AND → OR (one at a time)",
    apply = function(sql)
        return each_site(sql, "%f[%w](AND)%f[%W]", "OR", "%s → %s")
    end
})

--- 3. Flip comparison operators
table.insert(M.operators, {
    name = "flip_comparison",
    description = "Flip >, <, >=, <= boundaries",
    apply = function(sql)
        local mutations = {}
        -- >= → > (tighten)
        for _, m in ipairs(each_site(sql, "(>=)", ">", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- <= → < (tighten)
        for _, m in ipairs(each_site(sql, "(<=)", "<", "%s → %s")) do
            table.insert(mutations, m)
        end
        -- Find standalone > (not part of >= or ->)
        local search_start = 1
        while true do
            local s, e = sql:find(">", search_start, true)
            if not s then break end
            local next_char = sql:sub(e + 1, e + 1)
            local prev_char = sql:sub(s - 1, s - 1)
            if next_char ~= "=" and prev_char ~= "-" and prev_char ~= ">" then
                local mutated = sql:sub(1, s - 1) .. ">=" .. sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = "> → >=",
                    position = s
                })
            end
            search_start = e + 1
        end
        -- Find standalone < (not part of <= or <> or HTML tags)
        search_start = 1
        while true do
            local s, e = sql:find("<", search_start, true)
            if not s then break end
            local next_char = sql:sub(e + 1, e + 1)
            if next_char ~= "=" and next_char ~= ">" then
                local mutated = sql:sub(1, s - 1) .. "<=" .. sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = "< → <=",
                    position = s
                })
            end
            search_start = e + 1
        end
        return mutations
    end
})

--- 4. Swap NULL checks: IS NULL ↔ IS NOT NULL
table.insert(M.operators, {
    name = "swap_null",
    description = "IS NULL ↔ IS NOT NULL",
    apply = function(sql)
        local mutations = {}
        -- IS NOT NULL → IS NULL (skip SQL comments)
        for _, m in ipairs(each_site(sql, "(IS NOT NULL)", "IS NULL", "%s → %s")) do
            if not in_sql_comment(sql, m.position) then
                table.insert(mutations, m)
            end
        end
        -- IS NULL (not preceded by NOT) → IS NOT NULL (skip SQL comments)
        local search_start = 1
        while true do
            local s, e = sql:find("IS NULL", search_start, true)
            if not s then break end
            -- Check it's not "IS NOT NULL" and not in a comment
            local prefix = sql:sub(math.max(1, s - 4), s - 1)
            if not prefix:match("NOT $") and not in_sql_comment(sql, s) then
                local mutated = sql:sub(1, s - 1) .. "IS NOT NULL" .. sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = "IS NULL → IS NOT NULL",
                    position = s
                })
            end
            search_start = e + 1
        end
        return mutations
    end
})

--- 5. Change aggregate boundaries: HAVING COUNT(*) > N → > N-1 or > N+1
table.insert(M.operators, {
    name = "change_aggregate",
    description = "Shift HAVING threshold",
    apply = function(sql)
        local mutations = {}
        -- COUNT(*) > N → COUNT(*) > N-1 and COUNT(*) > N+1
        local search_start = 1
        while true do
            local s, e, num_str = sql:find("COUNT%(%*%) > (%d+)", search_start)
            if not s then break end
            local num = tonumber(num_str)
            -- > N → > N-1 (more permissive)
            if num > 0 then
                local mutated = sql:sub(1, s - 1) ..
                    "COUNT(*) > " .. (num - 1) ..
                    sql:sub(e + 1)
                table.insert(mutations, {
                    sql = mutated,
                    desc = string.format("COUNT(*) > %d → COUNT(*) > %d", num, num - 1),
                    position = s
                })
            end
            -- > N → >= N (boundary shift)
            local mutated2 = sql:sub(1, s - 1) ..
                "COUNT(*) >= " .. num_str ..
                sql:sub(e + 1)
            table.insert(mutations, {
                sql = mutated2,
                desc = string.format("COUNT(*) > %s → COUNT(*) >= %s", num_str, num_str),
                position = s
            })
            search_start = e + 1
        end
        return mutations
    end
})

--- 6. Drop WHERE predicate: remove one AND-connected predicate at a time
table.insert(M.operators, {
    name = "drop_predicate",
    description = "Remove one AND predicate from WHERE",
    apply = function(sql)
        local mutations = {}
        -- Find AND-delimited predicates in WHERE clauses and remove one at a time
        -- Match "  AND <predicate>" blocks (indented, multi-line aware)
        local search_start = 1
        while true do
            -- Match a full AND-prefixed predicate line
            local s, e = sql:find("\n%s+AND [^\n]+", search_start)
            if not s then break end
            local removed_text = sql:sub(s, e):match("^%s*(.-)%s*$")
            local mutated = sql:sub(1, s - 1) .. sql:sub(e + 1)
            table.insert(mutations, {
                sql = mutated,
                desc = "dropped: " .. removed_text:sub(1, 60),
                position = s
            })
            search_start = e + 1
        end
        return mutations
    end
})

---Generate all single-site mutations for a given SQL view definition.
---@param view_name string Name of the view (e.g., "view_float_orphan")
---@param sql string The CREATE VIEW SQL string
---@return table[] Array of {operator=string, sql=string, desc=string, position=number}
function M.generate_mutations(view_name, sql)
    local all = {}
    for _, op in ipairs(M.operators) do
        local mutations = op.apply(sql)
        for _, m in ipairs(mutations) do
            table.insert(all, {
                view = view_name,
                operator = op.name,
                sql = m.sql,
                desc = m.desc,
                position = m.position
            })
        end
    end
    return all
end

return M
