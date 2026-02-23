-- src/pipeline/verify/verify_handler.lua
-- Pipeline handler that runs all proof views during VERIFY phase.
-- Proof definitions are loaded from models via proof_loader (no hardcoded proofs).

local M = {
    name = "verify",
    prerequisites = {"relation_analyzer"}
}

local ProofLoader = require("core.proof_loader")

---Run a single proof view and collect violations
---@param data DataManager
---@param proof table Proof definition
---@param policy table|nil ValidationPolicy
---@return table[] violations
local function run_proof(data, proof, policy)
    local violations = {}

    -- INLINE SQL: proof.view is a runtime table name from model proof definitions
    local ok, rows = pcall(function()
        return data:query_all("SELECT * FROM " .. proof.view, {})
    end)

    if not ok then
        local level = "error"
        if policy and policy.get_level then
            local policy_level = policy:get_level(proof.policy_key)
            if policy_level then
                level = policy_level
            end
        end

        if level ~= "ignore" then
            table.insert(violations, {
                key = proof.policy_key,
                level = level,
                message = string.format(
                    "Validation query failed for proof view '%s': %s",
                    proof.view,
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
            local policy_level = policy:get_level(proof.policy_key)
            if policy_level then
                level = policy_level
            end
        end

        if level ~= "ignore" then
            table.insert(violations, {
                key = proof.policy_key,
                level = level,
                message = proof.message(row),
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

    -- Collect violations from all proof views and report to diagnostics in a single pass
    for _, proof in ipairs(ProofLoader.get_proofs()) do
        local violations = run_proof(data, proof, policy)
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
