-- Coverage collection wrapper for luacov with LCOV output
-- Provides per-suite coverage tracking with LCOV format output

local M = {}

-- State
M.enabled = false
M.current_suite = nil
M.report_dir = "tests/reports/coverage"
M._line_filter_cache = {}

--- Check if luacov is available
---@return boolean available
function M.is_available()
    local ok, _ = pcall(require, "luacov.runner")
    return ok
end

--- Initialize coverage for a test suite
---@param suite_name string Name of the test suite
---@param options table|nil Options: { include = {...}, exclude = {...} }
function M.start(suite_name, options)
    if not M.is_available() then
        io.stderr:write("[coverage] luacov not available, skipping coverage\n")
        return
    end

    -- Only initialize luacov once per process
    if M.enabled then
        return
    end

    options = options or {}
    M.current_suite = suite_name
    M.enabled = true

    -- Sanitize suite name for filename
    local safe_name = suite_name:gsub("[/\\]", "_"):gsub("%s+", "_"):gsub("[^%w_-]", "")

    -- Configure luacov with per-suite stats file
    local config = {
        -- Only track src/ files by default
        include = options.include or { "src/" },
        exclude = options.exclude or { "tests/", "vendor/", "luacov" },

        -- Per-suite stats file
        statsfile = string.format("%s/%s.stats", M.report_dir, safe_name),

        -- Don't run reporter automatically
        runreport = false,
    }

    -- Ensure report directory exists
    os.execute("mkdir -p " .. M.report_dir)

    -- Initialize luacov
    local ok, runner = pcall(require, "luacov.runner")
    if ok then
        runner.init(config)
    end
end

--- Stop coverage for current suite (no-op, we accumulate across suites)
function M.stop()
    -- No-op: we keep luacov running to accumulate stats across all suites
    -- Use finalize() at the end to save stats
end

--- Finalize coverage collection and save stats
function M.finalize()
    if not M.enabled then return end

    local ok, runner = pcall(require, "luacov.runner")
    if ok then
        runner.shutdown()
    end

    M.enabled = false
end

--- Generate LCOV report from stats file
---@param suite_name string Suite name
---@return string|nil lcov_path Path to LCOV file or nil on error
function M.generate_lcov(suite_name)
    local safe_name = suite_name:gsub("[/\\]", "_"):gsub("%s+", "_"):gsub("[^%w_-]", "")
    local stats_file = string.format("%s/%s.stats", M.report_dir, safe_name)
    local lcov_file = stats_file:gsub("%.stats$", ".lcov")

    -- Parse stats and generate LCOV format
    local stats = M.load_stats(stats_file)
    if not stats then
        return nil
    end

    local lcov = M.stats_to_lcov(stats)

    local f = io.open(lcov_file, "w")
    if f then
        f:write(lcov)
        f:close()
        return lcov_file
    end

    return nil
end

--- Load luacov stats file
--- Format: each file entry is "LINE_COUNT:FILE_PATH" followed by space-separated hit counts
---@param path string Stats file path
---@return table|nil stats Coverage statistics { [filename] = { [line] = count } }
function M.load_stats(path)
    local f = io.open(path, "r")
    if not f then return nil end

    local stats = {}
    local current_file = nil
    local expecting_counts = false

    for line in f:lines() do
        -- Format: "LINE_COUNT:FILE_PATH" e.g., "346:src/backend/assembler.lua"
        local line_count, file_path = line:match("^(%d+):(.+)$")
        if line_count and file_path then
            current_file = file_path
            stats[current_file] = {}
            expecting_counts = true
        elseif expecting_counts and current_file then
            -- Line of space-separated hit counts
            local line_num = 1
            for count_str in line:gmatch("%S+") do
                local count = tonumber(count_str)
                if count then
                    stats[current_file][line_num] = count
                    line_num = line_num + 1
                end
            end
            expecting_counts = false
        end
    end

    f:close()
    return stats
end

--- Read a file into an array of lines.
---@param path string
---@return table|nil
local function read_lines(path)
    local f = io.open(path, "r")
    if not f then
        return nil
    end
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    return lines
end

--- Build a map of line numbers that should count for coverage stats.
--- Excludes blank lines, comment-only lines, standalone `end`/`else` lines,
--- and body lines of Lua long-string literals (for multiline SQL/query text).
---@param path string
---@return table|nil keep_map
local function build_keep_line_map(path)
    local lines = read_lines(path)
    if not lines then
        return nil
    end

    local keep = {}
    local in_long_comment = false
    local long_comment_close = nil
    local in_long_string = false
    local long_string_close = nil

    for i, line in ipairs(lines) do
        local trimmed = line:match("^%s*(.-)%s*$")
        local include = true

        if in_long_comment then
            include = false
            if long_comment_close and line:find(long_comment_close, 1, true) then
                in_long_comment = false
                long_comment_close = nil
            end
        elseif in_long_string then
            include = false
            local close_pos = long_string_close and line:find(long_string_close, 1, true)
            if close_pos then
                local close_token = long_string_close
                in_long_string = false
                long_string_close = nil
                -- Keep closing line if there is executable code after the string.
                local after = line:sub(close_pos + #close_token)
                if after:match("%S") then
                    include = true
                end
            end
        elseif trimmed == "" then
            include = false
        else
            local eqs = trimmed:match("^%-%-%[(=*)%[")
            if eqs then
                include = false
                in_long_comment = true
                long_comment_close = "]" .. eqs .. "]"
            elseif trimmed:match("^%-%-") then
                include = false
            elseif trimmed:match("^end[%s,;]*$") or trimmed:match("^end[%s,;]*%-%-.*$") then
                include = false
            elseif trimmed:match("^else[%s,;]*$") or trimmed:match("^else[%s,;]*%-%-.*$") then
                include = false
            elseif trimmed:match("^[%[%]%(%)%{%},;]+$") or trimmed:match("^[%[%]%(%)%{%},;]+%s*%-%-.*$") then
                -- Delimiter-only structural lines (e.g., "})", "},", "]")
                -- carry no executable bytecode and should not count.
                include = false
            else
                -- Exclude body lines of Lua long strings ([[...]] / [=[...]=]).
                -- Keep the opening line if it also contains executable code before the opening delimiter.
                local open_pos, eqs2 = line:match("()%[(=*)%[")
                if open_pos then
                    local close_token = "]" .. eqs2 .. "]"
                    local close_pos = line:find(close_token, open_pos + 2 + #eqs2, true)
                    if not close_pos then
                        in_long_string = true
                        long_string_close = close_token
                        local before = line:sub(1, open_pos - 1)
                        if not before:match("%S") then
                            include = false
                        end
                    elseif not line:sub(1, open_pos - 1):match("%S") and not line:sub(close_pos + #close_token):match("%S") then
                        -- String-only single line literal.
                        include = false
                    end
                end
            end
        end

        keep[i] = include
    end

    return keep
end

--- Return whether a line should contribute to coverage metrics.
---@param path string
---@param line_num integer
---@return boolean
local function should_count_line(path, line_num)
    local keep_map = M._line_filter_cache[path]
    if keep_map == nil then
        keep_map = build_keep_line_map(path)
        -- Cache false when file cannot be read to avoid repeated IO failures.
        M._line_filter_cache[path] = keep_map or false
    elseif keep_map == false then
        keep_map = nil
    end

    if not keep_map then
        -- If source file is missing, keep legacy behavior.
        return true
    end

    return keep_map[line_num] == true
end

--- Convert stats to LCOV format
---@param stats table Coverage statistics
---@return string lcov LCOV format string
function M.stats_to_lcov(stats)
    local lines = {}

    for file, file_stats in pairs(stats) do
        -- SF: source file
        table.insert(lines, "SF:" .. file)

        local lines_found = 0
        local lines_hit = 0

        -- DA: line data (line_number, execution_count)
        local line_nums = {}
        for ln, _ in pairs(file_stats) do
            table.insert(line_nums, ln)
        end
        table.sort(line_nums)

        for _, ln in ipairs(line_nums) do
            local count = file_stats[ln]
            if should_count_line(file, ln) then
                table.insert(lines, string.format("DA:%d,%d", ln, count))
                lines_found = lines_found + 1
                if count > 0 then
                    lines_hit = lines_hit + 1
                end
            end
        end

        -- LF: lines found, LH: lines hit
        table.insert(lines, "LF:" .. lines_found)
        table.insert(lines, "LH:" .. lines_hit)

        -- end_of_record
        table.insert(lines, "end_of_record")
    end

    return table.concat(lines, "\n") .. "\n"
end

--- Merge multiple LCOV files into one
---@param lcov_files table Array of LCOV file paths
---@param output_path string Output merged LCOV file path
---@return boolean success
function M.merge_lcov(lcov_files, output_path)
    local merged = {}

    for _, lcov_file in ipairs(lcov_files) do
        local f = io.open(lcov_file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            table.insert(merged, content)
        end
    end

    local f = io.open(output_path, "w")
    if f then
        f:write(table.concat(merged, "\n"))
        f:close()
        return true
    end

    return false
end

--- Get list of all LCOV files in report directory
---@return table lcov_files Array of LCOV file paths
function M.get_lcov_files()
    local files = {}
    local handle = io.popen("ls " .. M.report_dir .. "/*.lcov 2>/dev/null")
    if handle then
        for file in handle:lines() do
            table.insert(files, file)
        end
        handle:close()
    end
    return files
end

--- Generate HTML coverage report from LCOV file
--- Uses genhtml (from lcov) for detailed line-by-line coverage, falls back to built-in summary
---@param suite_name string Suite name for the report
---@param output_dir string|nil Output directory (default: report_dir/html/<suite_name>)
---@return string|nil html_dir Path to HTML directory or nil on error
function M.generate_html(suite_name, output_dir)
    local safe_name = suite_name:gsub("[/\\]", "_"):gsub("%s+", "_"):gsub("[^%w_-]", "")
    local lcov_file = string.format("%s/%s.lcov", M.report_dir, safe_name)

    -- Check if LCOV file exists
    local f = io.open(lcov_file, "r")
    if not f then
        io.stderr:write("[coverage] LCOV file not found: " .. lcov_file .. "\n")
        return nil
    end
    f:close()

    output_dir = output_dir or string.format("%s/html/%s", M.report_dir, safe_name)

    -- Prefer genhtml for detailed line-by-line coverage
    local handle = io.popen("which genhtml 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result ~= "" then
            os.execute("mkdir -p " .. output_dir)
            local cmd = string.format(
                'genhtml "%s" --output-directory "%s" --title "Coverage: %s" --legend --ignore-errors empty --quiet 2>/dev/null',
                lcov_file, output_dir, suite_name
            )
            os.execute(cmd)
            if io.open(output_dir .. "/index.html", "r") then
                return output_dir
            end
        end
    end

    -- Fallback: use built-in HTML generator (summary only)
    local ok, html_report = pcall(require, "helpers.html_report")
    if ok then
        if html_report.generate(lcov_file, output_dir, suite_name) then
            return output_dir
        end
    end

    io.stderr:write("[coverage] No HTML reporter available (install lcov for detailed reports)\n")
    return nil
end

--- Generate HTML report from all coverage data (merged)
---@param output_dir string|nil Output directory (default: report_dir/html/merged)
---@param title string|nil Report title
---@return string|nil html_dir Path to HTML directory or nil on error
function M.generate_html_merged(output_dir, title)
    local lcov_files = M.get_lcov_files()

    if #lcov_files == 0 then
        io.stderr:write("[coverage] No LCOV files found to generate HTML report\n")
        return nil
    end

    output_dir = output_dir or (M.report_dir .. "/html/merged")
    title = title or "SpecCompiler Coverage (All Suites)"

    -- Merge all LCOV files
    local merged_lcov = M.report_dir .. "/merged.lcov"
    if #lcov_files > 1 then
        if not M.merge_lcov(lcov_files, merged_lcov) then
            io.stderr:write("[coverage] Failed to merge LCOV files\n")
            return nil
        end
    else
        merged_lcov = lcov_files[1]
    end

    -- Prefer genhtml for detailed line-by-line coverage
    local handle = io.popen("which genhtml 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        if result and result ~= "" then
            os.execute("mkdir -p " .. output_dir)
            local cmd = string.format(
                'genhtml "%s" --output-directory "%s" --title "%s" --legend --ignore-errors empty --quiet 2>/dev/null',
                merged_lcov, output_dir, title
            )
            os.execute(cmd)
            if io.open(output_dir .. "/index.html", "r") then
                return output_dir
            end
        end
    end

    -- Fallback: use built-in HTML generator (summary only)
    local ok, html_report = pcall(require, "helpers.html_report")
    if ok then
        if html_report.generate(merged_lcov, output_dir, title) then
            return output_dir
        end
    end

    return nil
end

return M
