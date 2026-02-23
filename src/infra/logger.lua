-- src/infra/logger.lua
-- Logging system with TTY-aware output (console vs JSON)
local json = require("dkjson")

local M = {}

--- Level thresholds for filtering
local LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

--- Logger state (configured via M.configure())
local state = {
    level = LEVELS.INFO,
    format = "auto",   -- "auto" | "json" | "console"
    color = true,
    is_tty = nil,      -- cached TTY detection result
}

--- ANSI color codes
local colors = {
    reset = "\27[0m",
    dim = "\27[2m",
    bold = "\27[1m",
    red = "\27[31m",
    yellow = "\27[33m",
    gray = "\27[90m",
}

--- Detect if stderr is a TTY
---@return boolean
local function detect_tty()
    -- Try luaposix first (most reliable)
    local ok, posix = pcall(require, "posix.unistd")
    if ok and posix.isatty then
        return posix.isatty(2) == 1
    end

    -- Fallback: check TERM environment variable
    local term = os.getenv("TERM")
    if not term or term == "" or term == "dumb" then
        return false
    end

    -- If we have a TERM and no CI indicators, assume TTY
    local ci = os.getenv("CI") or os.getenv("GITHUB_ACTIONS") or os.getenv("JENKINS_URL")
    return not ci
end

--- Check if we should use console output
---@return boolean
local function use_console()
    if state.format == "json" then
        return false
    elseif state.format == "console" then
        return true
    else
        -- auto mode: detect TTY
        if state.is_tty == nil then
            state.is_tty = detect_tty()
        end
        return state.is_tty
    end
end

--- Check if colors are enabled
---@return boolean
local function use_colors()
    if not state.color then
        return false
    end
    -- Respect NO_COLOR standard (https://no-color.org/)
    if os.getenv("NO_COLOR") then
        return false
    end
    return use_console()
end

--- Get timestamp string (HH:MM:SS.mmm)
---@return string
local function timestamp()
    -- Try to get milliseconds via luasocket
    local ok, socket = pcall(require, "socket")
    if ok and socket.gettime then
        local t = socket.gettime()
        local ms = math.floor((t % 1) * 1000)
        return os.date("%H:%M:%S", math.floor(t)) .. string.format(".%03d", ms)
    end
    -- Fallback: seconds only
    return os.date("%H:%M:%S")
end

--- Format level string with optional color
---@param level string
---@param is_diagnostic boolean
---@return string
local function format_level(level, is_diagnostic)
    local upper = level:upper()
    local padded = string.format("%-5s", upper)

    if not use_colors() then
        return padded
    end

    if upper == "DEBUG" then
        return colors.gray .. padded .. colors.reset
    elseif upper == "INFO" then
        return padded
    elseif upper == "WARN" or upper == "WARNING" then
        return colors.yellow .. padded .. colors.reset
    elseif upper == "ERROR" then
        return colors.bold .. colors.red .. padded .. colors.reset
    else
        return padded
    end
end

--- Emit a log entry (operational/progress info)
---@param level string "debug" | "info" | "progress"
---@param message string
---@param extra table|nil Additional fields
function M.log(level, message, extra)
    -- Level filtering
    local level_num = LEVELS[level:upper()] or LEVELS.INFO
    if level_num < state.level then
        return
    end

    if use_console() then
        -- Console format
        local parts = {}

        -- Timestamp only in DEBUG mode
        if state.level == LEVELS.DEBUG then
            local ts = timestamp()
            if use_colors() then
                table.insert(parts, colors.dim .. ts .. colors.reset)
            else
                table.insert(parts, ts)
            end
        end

        table.insert(parts, format_level(level, false))
        table.insert(parts, message)

        io.stderr:write(table.concat(parts, " ") .. "\n")
    else
        -- JSON format
        local entry = {
            type = "log",
            level = level,
            message = message,
            ts = timestamp()
        }
        for k, v in pairs(extra or {}) do
            entry[k] = v
        end
        io.stderr:write(json.encode(entry) .. "\n")
    end
    io.stderr:flush()
end

--- Emit a diagnostic entry (actionable user feedback)
---@param level string "error" | "warning" | "info"
---@param message string
---@param source string|nil File path
---@param line number|nil Line number
function M.diagnostic(level, message, source, line)
    if use_console() then
        -- Console format
        local parts = {}

        -- Timestamp only in DEBUG mode
        if state.level == LEVELS.DEBUG then
            local ts = timestamp()
            if use_colors() then
                table.insert(parts, colors.dim .. ts .. colors.reset)
            else
                table.insert(parts, ts)
            end
        end

        table.insert(parts, format_level(level, true))

        -- Add source:line if present
        if source then
            local loc = source
            if line and line > 0 then
                loc = loc .. ":" .. tostring(line)
            end
            table.insert(parts, loc)
        end

        table.insert(parts, message)

        io.stderr:write(table.concat(parts, " ") .. "\n")
    else
        -- JSON format
        local entry = {
            type = "diagnostic",
            level = level,
            message = message,
            source = source,
            line = line,
            ts = timestamp()
        }
        io.stderr:write(json.encode(entry) .. "\n")
    end
    io.stderr:flush()
end

--- Configure the logger (call after loading config.lua)
---@param opts table|nil Logging configuration
function M.configure(opts)
    opts = opts or {}
    if opts.level then
        state.level = LEVELS[opts.level:upper()] or LEVELS.INFO
    end
    if opts.format then
        state.format = opts.format
    end
    if opts.color ~= nil then
        state.color = opts.color
    end
    -- Reset TTY cache when format changes
    state.is_tty = nil
end

--- Convenience methods for logs
function M.info(msg, extra) M.log("info", msg, extra) end
function M.debug(msg, extra) M.log("debug", msg, extra) end
function M.progress(msg, current, total) M.log("progress", msg, {current=current, total=total}) end

--- Convenience methods for diagnostics
function M.error(msg, source, line) M.diagnostic("error", msg, source, line) end
function M.warning(msg, source, line) M.diagnostic("warning", msg, source, line) end
function M.success(msg) M.diagnostic("info", msg) end

---Create a log adapter with conventional log.debug(), log.info(), etc. methods.
---Used by modules that prefer object-style logging.
---@param level string|nil Minimum log level ("DEBUG", "INFO", "WARN", "ERROR")
---@return table log Log object with debug, info, warn, error methods
function M.create_adapter(level)
    local threshold = LEVELS[level] or state.level

    return {
        debug = function(fmt, ...)
            if threshold <= LEVELS.DEBUG then
                local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
                M.log("debug", msg)
            end
        end,
        info = function(fmt, ...)
            if threshold <= LEVELS.INFO then
                local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
                M.log("info", msg)
            end
        end,
        warn = function(fmt, ...)
            if threshold <= LEVELS.WARN then
                local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
                M.diagnostic("warning", msg)
            end
        end,
        error = function(fmt, ...)
            if threshold <= LEVELS.ERROR then
                local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
                M.diagnostic("error", msg)
            end
        end
    }
end

return M
