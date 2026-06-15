-- src/pipeline/verify/verify_handler.lua
-- Pipeline handler that runs all verification views during VERIFY phase.
-- Verification view definitions come from the host registry via host:get_verification_views().

local M = {
    name = "verify",
    prerequisites = {"relation_analyzer"}
}

local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

---Run a single verification view and collect violations
---@param data DataManager
---@param verification_view table Verification view definition
---@param policy table|nil ValidationPolicy
---@param pctx table per-spec pipeline context (for the canonical message ctx)
---@param diagnostics table diagnostics collector
---@return table[] violations
local function run_verification_view(data, verification_view, policy, pctx, diagnostics)
    local violations = {}

    -- Resolve the policy level once per view (applies to the query-failure
    -- branch and every violation row alike).
    local level = "error"
    if policy and policy.get_level then
        local policy_level = policy:get_level(verification_view.policy_key)
        if policy_level then
            level = policy_level
        end
    end

    -- INLINE SQL: verification_view.view is a runtime table name from model verification view definitions
    local ok, rows = pcall(function()
        return data:query_all("SELECT * FROM " .. verification_view.view, {})
    end)

    if not ok then
        if level ~= "ignore" then
            table.insert(violations, {
                key = verification_view.policy_key,
                level = level,
                message = string.format(
                    "Validation query failed for verification view '%s': %s",
                    verification_view.view,
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
                key = verification_view.policy_key,
                level = level,
                message = verification_view.message(row_ctx),
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
function M.on_verify(data, contexts, diagnostics)
    -- Get validation policy from first context (shared config)
    local policy = nil
    local ok, ValidationPolicy = pcall(require, 'core.validation_policy')
    if ok and contexts[1] then
        policy = ValidationPolicy.new({ validation = contexts[1].validation })
    end

    local all_violations = {}
    local error_count = 0
    local warn_count = 0

    -- Collect violations from all verification views and report to diagnostics
    -- in a single pass. The host owns the ordered policy_key registry.
    local host = registry.current()
    local verification_views = host and host:get_verification_views() or {}
    for _, verification_view in ipairs(verification_views) do
        local violations = run_verification_view(data, verification_view, policy, contexts[1], diagnostics)
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
