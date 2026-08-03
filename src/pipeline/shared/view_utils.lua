---View utilities for SpecCompiler.
---Shared helpers for inline view rendering.
---
---@module view_utils
local M = {}

---Parse `key=value` params from inline view content (the text after `prefix:`).
---Pairs are space- or comma-separated; numeric values are coerced to numbers
---(same convention as chart data-view params in data_loader).
---@param content string|nil Content portion of an inline view
---@return table params Parsed key -> value map (possibly empty)
function M.parse_params(content)
    local params = {}
    for key, value in (content or ""):gmatch("([%w_]+)%s*=%s*([^%s,]+)") do
        params[key] = tonumber(value) or value
    end
    return params
end

---Build a link target for a PID: internal (#pid) for same-document targets,
---external ({spec}.ext#pid) for cross-document targets.
---@param pid string Target object PID
---@param target_spec string Specification the target lives in
---@param current_spec string Specification being rendered
---@return string target
function M.make_link_target(pid, target_spec, current_spec)
    if target_spec == current_spec then
        return "#" .. pid
    else
        return target_spec .. ".ext#" .. pid
    end
end

return M
