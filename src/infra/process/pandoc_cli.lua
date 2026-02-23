---Pandoc CLI command builder for external process invocation.
---Builds command-line arguments from configuration for parallel execution.
---
---@module pandoc_cli
local M = {}

-- ============================================================================
-- Filter Resolution
-- ============================================================================

---Check if a file exists.
---@param path string File path to check
---@return boolean exists True if file exists
local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

---Get speccompiler home directory (where models/ lives).
---@return string speccompiler_home Absolute path to speccompiler installation
function M.get_speccompiler_home()
    -- Check environment variable first
    local env_home = os.getenv("SPECCOMPILER_HOME")
    if env_home then
        return env_home
    end

    -- Fall back to path from this module
    -- This file is at src/backend/pandoc_cli.lua, so ../../ gets to root
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local this_file = info.source:sub(2)
        -- Make path absolute if it isn't already
        if not this_file:match("^/") then
            local pwd = io.popen("pwd"):read("*l")
            if pwd then
                this_file = pwd .. "/" .. this_file
            end
        end
        -- Normalize the path by resolving .. components
        local parts = {}
        for part in this_file:gmatch("[^/]+") do
            if part == ".." then
                table.remove(parts)
            elseif part ~= "." then
                table.insert(parts, part)
            end
        end
        -- Get directory containing this file, then go up 2 levels
        local dir = "/" .. table.concat(parts, "/")
        dir = dir:match("^(.+)/[^/]+$")  -- Remove filename
        dir = dir:match("^(.+)/[^/]+$")  -- Remove backend/
        dir = dir:match("^(.+)/[^/]+$")  -- Remove src/
        if dir then
            return dir
        end
    end

    -- Last resort: current directory
    return "."
end

---Resolve filter path from specification.
---Filter specs can be:
---  - Absolute path: /path/to/filter.lua
---  - Project-relative: ./filters/custom.lua
---  - Format name: docx, html, markdown (resolves to models/{template}/filters/{format}.lua)
---
---@param filter_spec string Filter specification
---@param format string Output format (used for default filter name)
---@param template string Template name (default: "default")
---@param project_root string Project root directory
---@return string|nil filter_path Resolved absolute path, or nil if not found
function M.resolve_filter_path(filter_spec, format, template, project_root)
    template = template or "default"

    -- Absolute path
    if filter_spec:match("^/") then
        if file_exists(filter_spec) then
            return filter_spec
        end
        return nil
    end

    -- Project-relative path (starts with ./)
    if filter_spec:match("^%./") then
        local path = project_root .. "/" .. filter_spec:sub(3)
        if not path:match("%.lua$") then
            path = path .. ".lua"
        end
        if file_exists(path) then
            return path
        end
        return nil
    end

    local speccompiler_home = M.get_speccompiler_home()
    local filter_name = filter_spec

    -- Try template-specific filter first
    local template_path = string.format("%s/models/%s/filters/%s.lua",
        speccompiler_home, template, filter_name)
    if file_exists(template_path) then
        return template_path
    end

    -- Fall back to default model
    if template ~= "default" then
        local default_path = string.format("%s/models/default/filters/%s.lua",
            speccompiler_home, filter_name)
        if file_exists(default_path) then
            return default_path
        end
    end

    return nil
end

---Build pandoc command-line arguments from format configuration.
---@param format string Output format (html5, docx, pdf, etc.)
---@param format_config table Format-specific configuration from project.yaml
---@param input_file string Path to input JSON file
---@param output_file string Path to output file
---@param project_root string Project root directory for resolving relative paths
---@param template string Template name for filter resolution (default: "default")
---@return table args Array of command-line arguments
local function resolve_project_path(path, project_root)
    if not path then return nil end
    if not path:match("^/") and project_root then
        return project_root .. "/" .. path
    end
    return path
end

local function append_common_options(args, format_config)
    if format_config.number_sections then
        table.insert(args, "--number-sections")
    end
    if format_config.table_of_contents then
        table.insert(args, "--toc")
    end
    if format_config.toc_depth then
        table.insert(args, "--toc-depth=" .. tostring(format_config.toc_depth))
    end
end

local function append_html_options(args, format, format_config)
    if format ~= "html5" and format ~= "html" then
        return
    end
    if format_config.standalone then
        table.insert(args, "--standalone")
    end
    if format_config.embed_resources then
        table.insert(args, "--embed-resources")
    end
    if format_config.resource_path then
        table.insert(args, "--resource-path=" .. format_config.resource_path)
    end
    if format_config.section_divs then
        table.insert(args, "--section-divs")
    end
    if format_config.html_q_tags then
        table.insert(args, "--html-q-tags")
    end
    if format_config.email_obfuscation then
        table.insert(args, "--email-obfuscation=" .. format_config.email_obfuscation)
    end
end

local function append_docx_options(args, format, format_config, project_root)
    if format ~= "docx" then
        return
    end
    if format_config.reference_doc then
        local ref_doc = resolve_project_path(format_config.reference_doc, project_root)
        table.insert(args, "--reference-doc=" .. ref_doc)
    end
    if format_config.resource_path then
        table.insert(args, "--resource-path=" .. format_config.resource_path)
    end
end

local function append_pdf_options(args, format, format_config)
    if format ~= "pdf" then
        return
    end
    if format_config.pdf_engine then
        table.insert(args, "--pdf-engine=" .. format_config.pdf_engine)
    end
    if format_config.pdf_engine_opt then
        if type(format_config.pdf_engine_opt) == "table" then
            for _, opt in ipairs(format_config.pdf_engine_opt) do
                table.insert(args, "--pdf-engine-opt=" .. opt)
            end
        else
            table.insert(args, "--pdf-engine-opt=" .. format_config.pdf_engine_opt)
        end
    end
end

local function append_latex_options(args, format, format_config, project_root)
    if format ~= "latex" and format ~= "tex" then
        return
    end

    table.insert(args, "--standalone")

    if format_config.top_level_division then
        table.insert(args, "--top-level-division=" .. format_config.top_level_division)
    end

    if format_config.template then
        local tpl_path = resolve_project_path(format_config.template, project_root)
        if file_exists(tpl_path) then
            table.insert(args, "--template=" .. tpl_path)
        else
            io.stderr:write(string.format("Warning: LaTeX template not found: %s\n", tpl_path))
        end
    end

    if format_config.include_in_header then
        local header_path = resolve_project_path(format_config.include_in_header, project_root)
        if file_exists(header_path) then
            table.insert(args, "--include-in-header=" .. header_path)
        else
            io.stderr:write(string.format("Warning: Header file not found: %s\n", header_path))
        end
    end

    if format_config.variables then
        for key, value in pairs(format_config.variables) do
            table.insert(args, "-V")
            table.insert(args, key .. "=" .. tostring(value))
        end
    end
end

local function append_citation_options(args, format_config, project_root, template)
    if format_config.bibliography then
        local bib_path = resolve_project_path(format_config.bibliography, project_root)
        if file_exists(bib_path) then
            table.insert(args, "--bibliography=" .. bib_path)
            table.insert(args, "--citeproc")
        else
            io.stderr:write(string.format("Warning: Bibliography file not found: %s\n", bib_path))
        end
    end

    if format_config.csl then
        local csl_path = resolve_project_path(format_config.csl, project_root)
        if file_exists(csl_path) then
            table.insert(args, "--csl=" .. csl_path)
        else
            -- Fallback: check model assets directory
            local speccompiler_home = M.get_speccompiler_home()
            local basename = format_config.csl:match("([^/]+)$")
            local model_csl = string.format("%s/models/%s/assets/%s",
                speccompiler_home, template or "default", basename)
            if file_exists(model_csl) then
                table.insert(args, "--csl=" .. model_csl)
            else
                io.stderr:write(string.format("Warning: CSL file not found: %s\n", csl_path))
            end
        end
    end
end

local function get_filter_format(format)
    if format == "html5" then return "html" end
    if format == "tex" then return "latex" end
    return format
end

local function append_filter_options(args, format, format_config, template, project_root)
    local filter_format = get_filter_format(format)
    local speccompiler_filter = M.resolve_filter_path(filter_format, format, template, project_root)
    if speccompiler_filter then
        table.insert(args, "--lua-filter=" .. speccompiler_filter)
    end

    if not format_config.filters then
        return
    end

    for _, filter_spec in ipairs(format_config.filters) do
        if filter_spec ~= filter_format then
            local filter_path = M.resolve_filter_path(filter_spec, format, template, project_root)
            if filter_path then
                table.insert(args, "--lua-filter=" .. filter_path)
            else
                io.stderr:write(string.format(
                    "Warning: Filter not found: %s (template=%s)\n", filter_spec, template))
            end
        end
    end
end

function M.build_args(format, format_config, input_file, output_file, project_root, template)
    local args = {}
    template = template or "default"
    format_config = format_config or {}

    table.insert(args, "-f")
    table.insert(args, "json")
    table.insert(args, "-t")
    table.insert(args, format)
    table.insert(args, "-o")
    table.insert(args, output_file)

    append_common_options(args, format_config)
    append_html_options(args, format, format_config)
    append_docx_options(args, format, format_config, project_root)
    append_pdf_options(args, format, format_config)
    append_latex_options(args, format, format_config, project_root)
    append_citation_options(args, format_config, project_root, template)
    append_filter_options(args, format, format_config, template, project_root)

    table.insert(args, input_file)
    return args
end

---Build a task descriptor for task_runner.spawn_batch.
---@param format string Output format
---@param format_config table Format configuration
---@param input_file string Input JSON file path
---@param output_file string Output file path
---@param project_root string Project root directory
---@param template string Template name for filter resolution
---@param context table Additional context to pass to result handler
---@return table task Task descriptor for task_runner
function M.build_task(format, format_config, input_file, output_file, project_root, template, context)
    local args = M.build_args(format, format_config, input_file, output_file, project_root, template)

    return {
        cmd = "pandoc",
        args = args,
        opts = {
            timeout = 120000  -- 2 minutes for complex documents
        },
        output_path = output_file,
        context = context or {}
    }
end

-- ============================================================================
-- Parse Task Builder (for parallel document parsing)
-- ============================================================================

---Build a task descriptor for parsing markdown to JSON AST.
---Used for parallel document parsing via subprocess spawning.
---@param input_path string Path to input markdown file
---@param output_path string Path to output JSON file
---@param opts table|nil Options: include_filter (path to include expansion filter)
---@return table task Task descriptor for task_runner
function M.build_parse_task(input_path, output_path, opts)
    opts = opts or {}
    local args = {}

    -- Input format: CommonMark with sourcepos for line tracking
    table.insert(args, "-f")
    table.insert(args, "commonmark_x+sourcepos")

    -- Output format: JSON AST
    table.insert(args, "-t")
    table.insert(args, "json")

    -- Output file
    table.insert(args, "-o")
    table.insert(args, output_path)

    -- Include expansion filter (handles recursive includes in subprocess)
    if opts.include_filter then
        table.insert(args, "--lua-filter=" .. opts.include_filter)
    end

    -- Input file (last argument)
    table.insert(args, input_path)

    return {
        cmd = "pandoc",
        args = args,
        opts = {
            timeout = opts.timeout or 60000  -- 1 minute default for parsing
        },
        input_path = input_path,
        output_path = output_path
    }
end

return M
