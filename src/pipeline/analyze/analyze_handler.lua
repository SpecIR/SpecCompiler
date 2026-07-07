-- src/pipeline/analyze/analyze_handler.lua
-- Pipeline handler that runs all analyze queries during ANALYZE phase.
-- Verification view definitions come from the host registry via host:get_analyze_queries().

local M = {
    name = "analyze",
    prerequisites = {"relation_resolver"}
}

local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

---Run a single analyze query and collect violations
---@param data DataManager
---@param analyze_query table Verification view definition
---@param policy table|nil ValidationPolicy
---@param pctx table per-spec pipeline context (for the canonical message ctx)
---@param diagnostics table diagnostics collector
---@return table[] violations
local function run_analyze_query(data, analyze_query, policy, pctx, diagnostics)
    local violations = {}

    -- Resolve the policy level once per view (applies to the query-failure
    -- branch and every violation row alike).
    local level = "error"
    if policy and policy.get_level then
        local policy_level = policy:get_level(analyze_query.policy_key)
        if policy_level then
            level = policy_level
        end
    end

    -- INLINE SQL: analyze_query.view is a runtime table name from model analyze query definitions
    local ok, rows = pcall(function()
        return data:query_all("SELECT * FROM " .. analyze_query.view, {})
    end)

    if not ok then
        if level ~= "ignore" then
            table.insert(violations, {
                key = analyze_query.policy_key,
                level = level,
                message = string.format(
                    "Validation query failed for analyze query '%s': %s",
                    analyze_query.view,
                    tostring(rows)
                ),
                file = nil,
                line = nil
            })
        end
        return violations
    end

    for _, row in ipairs(rows or {}) do
        if level ~= "ignore" then
            -- The message hook receives the canonical frozen ctx with the
            -- violation row as its subject.
            local row_ctx = hook_ctx.build(pctx, data, diagnostics, { row = row }, "message")
            table.insert(violations, {
                key = analyze_query.policy_key,
                level = level,
                message = analyze_query.message(row_ctx),
                file = row.from_file,
                line = row.start_line
            })
        end
    end

    return violations
end

---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_analyze(data, contexts, diagnostics)
    -- Get validation policy from first context (shared config)
    local policy = nil
    local ok, ValidationPolicy = pcall(require, 'core.validation_policy')
    if ok and contexts[1] then
        policy = ValidationPolicy.new({ validation = contexts[1].validation })
    end

    local all_violations = {}
    local error_count = 0
    local warn_count = 0

    -- Collect violations from all analyze queries and report to diagnostics
    -- in a single pass. The host owns the ordered policy_key registry.
    local host = registry.current()
    local analyze_queries = host and host:get_analyze_queries() or {}
    for _, analyze_query in ipairs(analyze_queries) do
        local violations = run_analyze_query(data, analyze_query, policy, contexts[1], diagnostics)
        for _, v in ipairs(violations) do
            table.insert(all_violations, v)
            if v.level == "error" then
                error_count = error_count + 1
                diagnostics:error(v.file, v.line, v.key, v.message)
            elseif v.level == "warn" then
                warn_count = warn_count + 1
                diagnostics:warn(v.file, v.line, v.key, v.message)
            end
        end
    end

    -- Store verification result in all contexts
    local verification_result = {
        error_count = error_count,
        warning_count = warn_count,
        has_errors = error_count > 0,
        violations = all_violations
    }
    for _, ctx in ipairs(contexts) do
        ctx.verification = verification_result
    end
end

return M
