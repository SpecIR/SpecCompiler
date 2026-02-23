-- Simple HTML coverage report generator
-- Generates HTML from LCOV files without external dependencies

local M = {}

--- HTML template for coverage report
local HTML_TEMPLATE = [[
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Coverage: %s</title>
    <style>
        :root {
            --bg: #1a1b26;
            --bg-light: #24283b;
            --text: #c0caf5;
            --text-dim: #565f89;
            --green: #9ece6a;
            --red: #f7768e;
            --yellow: #e0af68;
            --blue: #7aa2f7;
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.6;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 2rem; }
        h1 { color: var(--blue); margin-bottom: 1rem; }
        .summary {
            display: flex;
            gap: 2rem;
            margin-bottom: 2rem;
            padding: 1rem;
            background: var(--bg-light);
            border-radius: 8px;
        }
        .stat { text-align: center; }
        .stat-value { font-size: 2rem; font-weight: bold; }
        .stat-label { color: var(--text-dim); font-size: 0.875rem; }
        .coverage-high { color: var(--green); }
        .coverage-med { color: var(--yellow); }
        .coverage-low { color: var(--red); }
        table {
            width: 100%%;
            border-collapse: collapse;
            background: var(--bg-light);
            border-radius: 8px;
            overflow: hidden;
        }
        th, td {
            padding: 0.75rem 1rem;
            text-align: left;
            border-bottom: 1px solid var(--bg);
        }
        th { background: var(--bg); color: var(--blue); }
        tr:hover { background: rgba(122, 162, 247, 0.1); }
        .progress-bar {
            width: 100px;
            height: 8px;
            background: var(--bg);
            border-radius: 4px;
            overflow: hidden;
        }
        .progress-fill {
            height: 100%%;
            border-radius: 4px;
        }
        .file-link { color: var(--blue); text-decoration: none; }
        .file-link:hover { text-decoration: underline; }
        .timestamp { color: var(--text-dim); font-size: 0.875rem; margin-top: 2rem; }
    </style>
</head>
<body>
    <div class="container">
        <h1>%s</h1>
        <div class="summary">
            <div class="stat">
                <div class="stat-value">%d</div>
                <div class="stat-label">Files</div>
            </div>
            <div class="stat">
                <div class="stat-value %s">%.1f%%</div>
                <div class="stat-label">Line Coverage</div>
            </div>
            <div class="stat">
                <div class="stat-value">%d</div>
                <div class="stat-label">Lines Hit</div>
            </div>
            <div class="stat">
                <div class="stat-value">%d</div>
                <div class="stat-label">Total Lines</div>
            </div>
        </div>
        <table>
            <thead>
                <tr>
                    <th>File</th>
                    <th>Lines</th>
                    <th>Coverage</th>
                    <th></th>
                </tr>
            </thead>
            <tbody>
%s
            </tbody>
        </table>
        <p class="timestamp">Generated: %s</p>
    </div>
</body>
</html>
]]

local FILE_ROW_TEMPLATE = [[
                <tr>
                    <td><span class="file-link">%s</span></td>
                    <td>%d / %d</td>
                    <td class="%s">%.1f%%</td>
                    <td>
                        <div class="progress-bar">
                            <div class="progress-fill %s" style="width: %.1f%%"></div>
                        </div>
                    </td>
                </tr>
]]

--- Parse LCOV file and extract coverage data
---@param lcov_path string Path to LCOV file
---@return table|nil files Coverage data by file { [filename] = { lines_found, lines_hit } }
function M.parse_lcov(lcov_path)
    local f = io.open(lcov_path, "r")
    if not f then return nil end

    local files = {}
    local current_file = nil

    for line in f:lines() do
        local sf = line:match("^SF:(.+)$")
        if sf then
            current_file = sf
            files[current_file] = { lines_found = 0, lines_hit = 0 }
        end

        local lf = line:match("^LF:(%d+)$")
        if lf and current_file and files[current_file] then
            files[current_file].lines_found = tonumber(lf)
        end

        local lh = line:match("^LH:(%d+)$")
        if lh and current_file and files[current_file] then
            files[current_file].lines_hit = tonumber(lh)
        end

        if line == "end_of_record" then
            current_file = nil
        end
    end

    f:close()
    return files
end

--- Get coverage class based on percentage
---@param pct number Coverage percentage
---@return string class CSS class name
local function coverage_class(pct)
    if pct >= 80 then return "coverage-high"
    elseif pct >= 50 then return "coverage-med"
    else return "coverage-low"
    end
end

--- Generate HTML report from LCOV file
---@param lcov_path string Path to LCOV file
---@param output_dir string Output directory for HTML
---@param title string Report title
---@return boolean success
function M.generate(lcov_path, output_dir, title)
    local files = M.parse_lcov(lcov_path)
    if not files then
        io.stderr:write("[html_report] Failed to parse LCOV: " .. lcov_path .. "\n")
        return false
    end

    -- Calculate totals
    local total_files = 0
    local total_found = 0
    local total_hit = 0
    local file_list = {}

    for filename, data in pairs(files) do
        if data.lines_found > 0 then
            total_files = total_files + 1
            total_found = total_found + data.lines_found
            total_hit = total_hit + data.lines_hit
            table.insert(file_list, {
                name = filename,
                found = data.lines_found,
                hit = data.lines_hit,
                pct = (data.lines_hit / data.lines_found) * 100
            })
        end
    end

    -- Sort by filename
    table.sort(file_list, function(a, b) return a.name < b.name end)

    -- Generate file rows
    local rows = {}
    for _, file in ipairs(file_list) do
        local class = coverage_class(file.pct)
        table.insert(rows, string.format(FILE_ROW_TEMPLATE,
            file.name,
            file.hit, file.found,
            class, file.pct,
            class, file.pct
        ))
    end

    -- Calculate overall percentage
    local overall_pct = total_found > 0 and (total_hit / total_found) * 100 or 0
    local overall_class = coverage_class(overall_pct)

    -- Generate HTML
    local html = string.format(HTML_TEMPLATE,
        title,                          -- page title
        title,                          -- h1
        total_files,                    -- files count
        overall_class, overall_pct,     -- coverage %
        total_hit,                      -- lines hit
        total_found,                    -- total lines
        table.concat(rows, "\n"),       -- file rows
        os.date("%Y-%m-%d %H:%M:%S")    -- timestamp
    )

    -- Write to file
    os.execute("mkdir -p " .. output_dir)
    local out_path = output_dir .. "/index.html"
    local out = io.open(out_path, "w")
    if not out then
        io.stderr:write("[html_report] Failed to write: " .. out_path .. "\n")
        return false
    end

    out:write(html)
    out:close()
    return true
end

return M
