---Task Runner for SpecCompiler.
---Provides unified interface for spawning external processes.
---Uses luv (libuv bindings) for async I/O.
---
---@module task_runner
local M = {}

local uv = require("luv")

-- Default timeout in milliseconds
local DEFAULT_TIMEOUT_MS = 30000

-- Timeout for quick command existence checks
local COMMAND_CHECK_TIMEOUT_MS = 5000

-- Platform detection
local is_windows = package.config:sub(1, 1) == "\\"

-- Cached CPU count (detected once)
local cpu_count_cache = nil

---Close a libuv handle if it is still open.
---@param handle uv_handle_t|nil
local function safe_close(handle)
    if not handle then return end
    if handle.is_closing and handle:is_closing() then return end
    handle:close()
end

---Get the number of CPU cores available.
---Uses nproc on Linux, sysctl on macOS, NUMBER_OF_PROCESSORS on Windows.
---@return number cpu_count Number of CPU cores (defaults to 4 if detection fails)
function M.get_cpu_count()
    if cpu_count_cache then
        return cpu_count_cache
    end

    local count = 4  -- Default fallback

    if is_windows then
        local env_count = os.getenv("NUMBER_OF_PROCESSORS")
        if env_count then
            count = tonumber(env_count) or 4
        end
    else
        -- Try nproc first (Linux), then sysctl (macOS)
        local handle = io.popen("nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null")
        if handle then
            local result = handle:read("*a")
            handle:close()
            if result then
                count = tonumber(result:match("%d+")) or 4
            end
        end
    end

    cpu_count_cache = count
    return count
end

---Spawn a command synchronously and capture output.
---Blocks until the process completes or times out.
---@param cmd string Command to execute
---@param args table|nil Array of arguments
---@param opts table|nil Options: timeout (ms), cwd, log
---@return boolean success True if exit code was 0
---@return string stdout Captured stdout
---@return string stderr Captured stderr
---@return number exit_code Process exit code (-1 on timeout/spawn failure)
function M.spawn_sync(cmd, args, opts)
    opts = opts or {}

    local stdout_chunks = {}
    local stderr_chunks = {}
    local exit_code = nil
    local done = false
    local timed_out = false
    local process_exited = false
    local stdout_eof = false
    local stderr_eof = false

    -- Create pipes for stdout/stderr capture
    local stdout_pipe = uv.new_pipe(false)
    local stderr_pipe = uv.new_pipe(false)

    local log = opts.log

    local function maybe_done()
        if process_exited and stdout_eof and stderr_eof then
            done = true
        end
    end

    local handle, pid
    handle, pid = uv.spawn(cmd, {
        args = args,
        cwd = opts.cwd,
        stdio = { nil, stdout_pipe, stderr_pipe }
    }, function(code, signal)
        exit_code = code
        process_exited = true
        safe_close(handle)
        maybe_done()
    end)

    if not handle then
        local err_msg = "Failed to spawn '" .. cmd .. "': " .. tostring(pid)
        if log then log.error(err_msg) end
        safe_close(stdout_pipe)
        safe_close(stderr_pipe)
        return false, "", err_msg, -1
    end

    -- Start reading stdout/stderr
    stdout_pipe:read_start(function(err, data)
        if data then
            table.insert(stdout_chunks, data)
            return
        end
        pcall(function() stdout_pipe:read_stop() end)
        stdout_eof = true
        safe_close(stdout_pipe)
        maybe_done()
    end)

    stderr_pipe:read_start(function(err, data)
        if data then
            table.insert(stderr_chunks, data)
            return
        end
        pcall(function() stderr_pipe:read_stop() end)
        stderr_eof = true
        safe_close(stderr_pipe)
        maybe_done()
    end)

    -- Block until complete
    uv.update_time()  -- Sync cached clock before measuring timeout
    local start_time = uv.now()
    local timeout_ms = opts.timeout or DEFAULT_TIMEOUT_MS

    while not done do
        uv.run("once")

        if uv.now() - start_time > timeout_ms then
            timed_out = true
            if handle and not handle:is_closing() then
                handle:kill("sigterm")
            end
            for _ = 1, 10 do
                uv.run("once")
                if done then break end
            end
            if not done then
                pcall(function() stdout_pipe:read_stop() end)
                pcall(function() stderr_pipe:read_stop() end)
                safe_close(stdout_pipe)
                safe_close(stderr_pipe)
                safe_close(handle)
                done = true
            end
            break
        end
    end

    local stdout = table.concat(stdout_chunks)
    local stderr = table.concat(stderr_chunks)

    if timed_out then
        return false, stdout, "Timeout after " .. timeout_ms .. "ms", -1
    end

    return exit_code == 0, stdout, stderr, exit_code or -1
end

-- Cache for command existence checks (PATH doesn't change during a build)
local command_exists_cache = {}

---Check if a command exists in the system PATH.
---Results are cached for the lifetime of the process.
---@param cmd string Command name to check
---@return boolean exists True if command exists
function M.command_exists(cmd)
    if command_exists_cache[cmd] ~= nil then
        return command_exists_cache[cmd]
    end

    local success
    if is_windows then
        success = M.spawn_sync("where", { cmd }, { timeout = COMMAND_CHECK_TIMEOUT_MS })
    else
        success = M.spawn_sync("sh", { "-c", "command -v " .. cmd }, { timeout = COMMAND_CHECK_TIMEOUT_MS })
    end

    command_exists_cache[cmd] = success
    return success
end

---Ensure a directory exists, creating it if needed.
---@param dir string Directory path
---@return boolean success
function M.ensure_dir(dir)
    local stat = uv.fs_stat(dir)
    if stat then return true end

    -- Create directory
    local ok, err = uv.fs_mkdir(dir, 493)  -- 0755 octal
    if not ok then
        -- Try with parents
        local parent = dir:match("(.+)/[^/]+$")
        if parent then
            M.ensure_dir(parent)
            ok, err = uv.fs_mkdir(dir, 493)
        end
    end
    return ok ~= nil
end

---Write content to a file.
---@param path string File path
---@param content string Content to write
---@return boolean success
---@return string|nil error
function M.write_file(path, content)
    local fd, err = uv.fs_open(path, "w", 420)  -- 0644 octal
    if not fd then
        return false, "Failed to open file: " .. (err or "unknown")
    end

    local write_ok, write_err = uv.fs_write(fd, content)
    uv.fs_close(fd)

    if not write_ok then
        return false, "Failed to write file: " .. (write_err or "unknown")
    end

    return true
end

---Read content from a file.
---@param path string File path
---@return string|nil content
---@return string|nil error
function M.read_file(path)
    local stat = uv.fs_stat(path)
    if not stat then
        return nil, "File not found: " .. path
    end

    local fd, err = uv.fs_open(path, "r", 420)
    if not fd then
        return nil, "Failed to open file: " .. (err or "unknown")
    end

    local content, read_err = uv.fs_read(fd, stat.size)
    uv.fs_close(fd)

    if not content then
        return nil, "Failed to read file: " .. (read_err or "unknown")
    end

    return content
end

---Check if a file exists.
---@param path string File path
---@return boolean exists
function M.file_exists(path)
    local stat = uv.fs_stat(path)
    return stat ~= nil
end

---Spawn a command asynchronously.
---Returns immediately with a result handle.
---@param cmd string Command to execute
---@param args table|nil Array of arguments
---@param opts table|nil Options: cwd, timeout
---@return table result Handle with done, stdout, stderr, exit_code
function M.spawn_async(cmd, args, opts)
    opts = opts or {}
    local result = {
        done = false,
        stdout = {},
        stderr = {},
        exit_code = nil
    }

    local stdout_pipe = uv.new_pipe(false)
    local stderr_pipe = uv.new_pipe(false)
    local process_exited = false
    local stdout_eof = false
    local stderr_eof = false

    local function maybe_done()
        if process_exited and stdout_eof and stderr_eof then
            result.done = true
        end
    end

    local handle
    handle = uv.spawn(cmd, {
        args = args,
        cwd = opts.cwd,
        stdio = { nil, stdout_pipe, stderr_pipe }
    }, function(code)
        result.exit_code = code
        process_exited = true
        safe_close(handle)
        maybe_done()
    end)

    if not handle then
        result.done = true
        result.exit_code = -1
        safe_close(stdout_pipe)
        safe_close(stderr_pipe)
        return result
    end

    stdout_pipe:read_start(function(_, data)
        if data then
            table.insert(result.stdout, data)
            return
        end
        pcall(function() stdout_pipe:read_stop() end)
        stdout_eof = true
        safe_close(stdout_pipe)
        maybe_done()
    end)

    stderr_pipe:read_start(function(_, data)
        if data then
            table.insert(result.stderr, data)
            return
        end
        pcall(function() stderr_pipe:read_stop() end)
        stderr_eof = true
        safe_close(stderr_pipe)
        maybe_done()
    end)

    return result
end

---Spawn multiple commands in parallel with CPU-limited concurrency.
---Only runs up to `max_concurrent` processes at a time (defaults to CPU count).
---@param tasks table Array of {cmd, args, opts} tables
---@param max_concurrent number|nil Maximum concurrent processes (defaults to CPU count)
---@return table results Array of {task, result} pairs
function M.spawn_batch(tasks, max_concurrent)
    max_concurrent = max_concurrent or M.get_cpu_count()
    local results = {}
    local active = {}
    local next_task_idx = 1
    local total_tasks = #tasks

    -- Helper to start a task
    local function start_task(task_idx)
        local task = tasks[task_idx]
        local result = M.spawn_async(task.cmd, task.args, task.opts or {})
        table.insert(active, { task = task, result = result, idx = task_idx })
    end

    -- Start initial batch (up to max_concurrent)
    while next_task_idx <= total_tasks and #active < max_concurrent do
        start_task(next_task_idx)
        next_task_idx = next_task_idx + 1
    end

    -- Process until all complete
    while #active > 0 do
        uv.run("once")

        -- Check for completed tasks
        local still_active = {}
        for _, p in ipairs(active) do
            if p.result.done then
                -- Task completed, add to results
                table.insert(results, { task = p.task, result = p.result })

                -- Start next task if any remaining
                if next_task_idx <= total_tasks then
                    start_task(next_task_idx)
                    next_task_idx = next_task_idx + 1
                end
            else
                -- Still running
                table.insert(still_active, p)
            end
        end
        active = still_active
    end

    return results
end

-- Export constants
M.DEFAULT_TIMEOUT_MS = DEFAULT_TIMEOUT_MS
M.uv = uv

return M
