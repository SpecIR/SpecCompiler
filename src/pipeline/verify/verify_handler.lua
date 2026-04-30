-- src/pipeline/verify/verify_handler.lua
-- Pipeline handler that runs all verification views during VERIFY phase.
-- Verification view definitions are loaded from models via verification_view_loader.

local M = {
    name = "verify",
    prerequisites = {"relation_analyzer"}
}

local VerificationViewLoader = require("core.verification_view_loader")

---Run a single verification view and collect violations
---@param data DataManager
---@param verification_view table Verification view definition
---@param policy table|nil ValidationPolicy
---@return table[] violations
local function run_verification_view(data, verification_view, policy)
    local violations = {}

    -- INLINE SQL: verification_view.view is a runtime table name from model verification view definitions
    local ok, rows = pcall(function()
        return data:query_all("SELECT * FROM " .. verification_view.view, {})
    end)

    if not ok then
        local level = "error"
        if policy and policy.get_level then
            local policy_level = policy:get_level(verification_view.policy_key)
            if policy_level then
                level = policy_level
            end
        end

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
        local level = "error"
        if policy and policy.get_level then
            local policy_level = policy:get_level(verification_view.policy_key)
            if policy_level then
                level = policy_level
            end
        end

        if level ~= "ignore" then
            table.insert(violations, {
                key = verification_view.policy_key,
                level = level,
                message = verification_view.message(row),
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

    -- Collect violations from all verification views and report to diagnostics in a single pass
    for _, verification_view in ipairs(VerificationViewLoader.get_verification_views()) do
        local violations = run_verification_view(data, verification_view, policy)
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
