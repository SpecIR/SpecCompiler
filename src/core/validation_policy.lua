-- src/core/validation_policy.lua
-- Per-policy-key severity levels for analyze queries ("error" | "warn" |
-- "ignore"), defaulted from the host's registered views and overridable via
-- project.yaml `validation:`. Consumed by analyze_handler:get_level().
local M = {}

function M.new(config)
    -- Build default policies dynamically from the host's registered verification
    -- views (the host owns the ordered policy_key registry).
    local host = require("contract.registry").current()
    local default_policies = {}

    if host then
        for _, analyze_query in ipairs(host:get_analyze_queries()) do
            if analyze_query.policy_key then
                default_policies[analyze_query.policy_key] = "error"
            end
        end
    end

    local self = {
        policies = default_policies,
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

function M:get_level(policy_key)
    return self.policies[policy_key] or "warn"
end

return M
