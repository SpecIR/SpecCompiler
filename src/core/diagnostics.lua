---Simplified Diagnostics Engine for SpecCompiler.

local logger = require("infra.logger")

local M = {}

function M.new()
    local self = setmetatable({}, { __index = M })
    self.errors = {}
    self.warnings = {}
    return self
end

function M:error(file, line, code, msg)
    file = file or "unknown"
    line = tonumber(line) or 0
    code = code or "ERR"
    msg = msg or ""
    local err = { file = file, line = line, code = code, message = msg }
    table.insert(self.errors, err)
    local full_msg = string.format("[%s] %s", code, msg)
    logger.diagnostic("error", full_msg, file ~= "unknown" and file or nil, line > 0 and line or nil)
end

function M:warn(file, line, code, msg)
    file = file or "unknown"
    line = tonumber(line) or 0
    code = code or "WARN"
    msg = msg or ""
    local warn = { file = file, line = line, code = code, message = msg }
    table.insert(self.warnings, warn)
    local full_msg = string.format("[%s] %s", code, msg)
    logger.diagnostic("warning", full_msg, file ~= "unknown" and file or nil, line > 0 and line or nil)
end

function M:has_errors()
    return #self.errors > 0
end

-- Alias for handlers using add_warning(file, line, msg) signature
function M:add_warning(file, line, msg)
    self:warn(file, line, "WARN", msg)
end

return M
