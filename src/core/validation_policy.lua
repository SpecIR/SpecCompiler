-- src/core/validation_policy.lua
local M = {}

M.MODES = { ERROR = "error", WARN = "warn", IGNORE = "ignore" }

function M.new(config)
    -- Build default policies dynamically from registered proofs (all default to "error")
    local ok, ProofLoader = pcall(require, "core.proof_loader")
    local default_policies = {}

    if ok then
        for _, proof in ipairs(ProofLoader.get_proofs()) do
            if proof.policy_key then
                default_policies[proof.policy_key] = "error"
            end
        end
    end

    local self = {
        policies = default_policies,
        error_count = 0,
        warning_count = 0,
    }

    -- Override from config
    if config and config.validation then
        for k, v in pairs(config.validation) do
            if self.policies[k] ~= nil then
                self.policies[k] = v
            end
        end
    end

    return setmetatable(self, { __index = M })
end

function M:get_mode(violation_type)
    return self.policies[violation_type] or "warn"
end

function M:get_level(policy_key)
    return self:get_mode(policy_key)
end

function M:report(violation_type, message, diagnostics)
    local mode = self:get_mode(violation_type)

    if mode == "error" then
        self.error_count = self.error_count + 1
        if diagnostics and diagnostics.error then
            diagnostics:error(message, nil, nil, "VALIDATION")
        end
    elseif mode == "warn" then
        self.warning_count = self.warning_count + 1
        if diagnostics and diagnostics.warn then
            diagnostics:warn(message, nil, nil, "VALIDATION")
        end
    end
    -- ignore = do nothing
end

function M:should_fail_build()
    return self.error_count > 0
end

function M:reset()
    self.error_count = 0
    self.warning_count = 0
end

function M:get_summary()
    return {
        errors = self.error_count,
        warnings = self.warning_count
    }
end

return M
