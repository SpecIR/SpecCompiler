---Chart type module for SpecCompiler.
---Handles ECharts JSON configs rendering to PNG using Deno.
---Supports data injection via Lua views.
---
---Usage:
---  ```chart:my_chart{view="object_types_summary" model="abnt"}
---  {...echarts config...}
---  ```
---
---@module chart
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")
local data_loader = require("core.data_loader")
local external_render = require("pipeline.transform.external_render_handler")

local M = {}

M.float = {
    id = "CHART",
    long_name = "Chart",
    description = "An ECharts chart rendered to PNG",
    caption_format = "Figure",  -- Display as "Figura" in ABNT
    counter_group = "FIGURE",   -- Share counter with FIGURE and PLANTUML
    aliases = { "echarts", "echart" },
    style_id = "CHART",
    needs_external_render = true,
}

-- ============================================================================
-- Internal Helpers
-- ============================================================================

local CHARTS_DIR = "charts"
local DEFAULT_WIDTH = 600
local DEFAULT_HEIGHT = 400
local RENDER_SCRIPT = "echarts-render.ts"

---Normalize a path: strip trailing slashes and collapse multiple slashes.
---@param path string Path to normalize
---@return string Normalized path
local function normalize_path(path)
    if not path then return "" end
    -- Remove trailing slashes
    path = path:gsub("/+$", "")
    -- Collapse multiple slashes to single
    path = path:gsub("/+", "/")
    return path
end

local function hash_content(content)
    if pandoc and pandoc.sha1 then
        return pandoc.sha1(content)
    end
    local h = 0
    for i = 1, #content do
        h = (h * 31 + string.byte(content, i)) % 0x7FFFFFFF
    end
    return string.format("%08x", h)
end

---Find render script or compiled binary.
---@param speccompiler_home string|nil SPECCOMPILER_HOME environment variable
---@return string|nil path Path to script or binary
---@return boolean is_compiled True if path is a compiled binary (run directly), false if TypeScript (needs Deno)
local function find_render_script(speccompiler_home)
    local candidates = {}
    local deno_available = task_runner.command_exists("deno")
    local speccompiler_dist = os.getenv("SPECCOMPILER_DIST")

    local function add_ts_paths(prefix)
        table.insert(candidates, {path = prefix .. "/src/tools/" .. RENDER_SCRIPT, compiled = false})
        table.insert(candidates, {path = prefix .. "/src/utils/" .. RENDER_SCRIPT, compiled = false})
        table.insert(candidates, {path = prefix .. "/scripts/" .. RENDER_SCRIPT, compiled = false})
        table.insert(candidates, {path = prefix .. "/" .. RENDER_SCRIPT, compiled = false})
    end

    local function add_bin_path(prefix)
        table.insert(candidates, {path = prefix .. "/bin/echarts-render", compiled = true})
    end

    -- Check SPECCOMPILER_DIST first (where binaries live in dist/ layout)
    if speccompiler_dist then
        add_bin_path(speccompiler_dist)
    end

    if speccompiler_home then
        -- Prefer source renderer when Deno exists.
        if deno_available then
            add_ts_paths(speccompiler_home)
            add_bin_path(speccompiler_home)
        else
            add_bin_path(speccompiler_home)
            add_ts_paths(speccompiler_home)
        end
    end

    -- Fallback relative paths
    if deno_available then
        add_ts_paths(".")
        add_bin_path(".")
    else
        add_bin_path(".")
        add_ts_paths(".")
    end

    for _, candidate in ipairs(candidates) do
        if task_runner.file_exists(candidate.path) then
            if candidate.compiled or deno_available then
                return candidate.path, candidate.compiled
            end
        end
    end

    return nil, false
end

---Parse chart config JSON and inject data if needed.
---@param raw_content string Raw JSON content
---@param attrs table Attributes (view, model, params, etc.)
---@param data DataManager Database instance
---@param log table Logger
---@return string json_content Modified JSON with injected data
---@return string|nil error Error message if data injection failed
local function prepare_chart_config(raw_content, attrs, data, log)
    local json_content = raw_content or '{}'

    -- Parse the JSON config
    local ok, config = pcall(function()
        if pandoc and pandoc.json and pandoc.json.decode then
            return pandoc.json.decode(json_content)
        end
        return nil, "JSON parsing not available without Pandoc"
    end)

    if not ok or not config then
        return json_content, nil
    end

    -- Check if data injection is needed
    if attrs.view then
        local injected_config, err = data_loader.inject_chart_data(config, attrs, data, log)
        if err then
            log.warn("Data injection failed: %s", err)
            return json_content, err
        end

        if pandoc and pandoc.json and pandoc.json.encode then
            return pandoc.json.encode(injected_config), nil
        end
    end

    return json_content, nil
end

local function serialize_result(result)
    if result and result.png_path then
        return '{"png_path":"' .. result.png_path:gsub('"', '\\"') .. '"}'
    end
    return nil
end

-- ============================================================================
-- External Render Registration
-- ============================================================================

external_render.register_renderer("CHART", {
    ---Prepare a spawn task for this float.
    ---@param float table Float record from database
    ---@param build_dir string Build directory path
    ---@param log table Logger
    ---@param data DataManager Database instance for data injection
    ---@param model_name string Model name from project config (e.g., "abnt")
    ---@return table|nil task Task descriptor or nil to skip
    prepare_task = function(float, build_dir, log, data, model_name)
        local attrs = float_base.decode_attributes(float)

        -- Start with raw content
        local json_content = float.raw_content or '{}'

        -- Map query/generator to view for data injection
        -- Charts use: view="view_name" for Lua view modules
        local view_name = attrs.query or attrs.generator or attrs.view
        if view_name and data then
            -- Create attrs copy with view set for data_loader
            -- Use model from attrs if specified, otherwise use project model
            local inject_attrs = {}
            for k, v in pairs(attrs) do inject_attrs[k] = v end
            inject_attrs.view = view_name
            inject_attrs.model = inject_attrs.model or model_name or "default"
            inject_attrs.spec_id = float.specification_ref or "default"

            local injected, err = prepare_chart_config(json_content, inject_attrs, data, log)
            if err then
                log.warn("Chart data injection failed for %s: %s", tostring(float.id), err)
            elseif injected and injected ~= json_content then
                json_content = injected
                log.debug("Injected data into chart: %s", tostring(float.id))
            end
        end

        local hash = hash_content(json_content)

        local width = tonumber(attrs.width) or DEFAULT_WIDTH
        local height = tonumber(attrs.height) or DEFAULT_HEIGHT

        -- Normalize build_dir to avoid double slashes
        local norm_build_dir = normalize_path(build_dir)
        local charts_path = norm_build_dir .. "/" .. CHARTS_DIR
        task_runner.ensure_dir(charts_path)

        local json_file = charts_path .. "/" .. hash .. ".json"
        local png_file = charts_path .. "/" .. hash .. ".png"
        -- Store relative path for LaTeX (relative to output file which is in build_dir)
        local relative_png = CHARTS_DIR .. "/" .. hash .. ".png"

        local render_script, is_compiled = find_render_script(os.getenv("SPECCOMPILER_HOME"))
        if not render_script then
            log.warn("ECharts render script not found")
            return nil
        end

        local write_ok, write_err = task_runner.write_file(json_file, json_content)
        if not write_ok then
            log.warn("Failed to write JSON config: %s", write_err or "unknown")
            return nil
        end

        log.info("Preparing chart: %s", hash:sub(1, 12))

        -- Build command based on whether we have compiled binary or TypeScript source
        local cmd, args
        if is_compiled then
            cmd = render_script
            args = { json_file, png_file, tostring(width), tostring(height) }
        else
            cmd = "deno"
            args = {
                "run", "--allow-read", "--allow-write", "--allow-env",
                "--allow-net", "--allow-ffi", "--allow-sys",
                render_script, json_file, png_file,
                tostring(width), tostring(height)
            }
        end

        return {
            cmd = cmd,
            args = args,
            opts = { timeout = 60000 },
            output_path = png_file,
            context = {
                hash = hash,
                float = float,
                attrs = attrs,
                relative_path = relative_png  -- Path relative to output file (for LaTeX)
            }
        }
    end,

    ---Handle result after spawn completes.
    ---@param task table Task descriptor with context
    ---@param success boolean Whether spawn succeeded
    ---@param stdout string Captured stdout
    ---@param stderr string Captured stderr
    ---@param data DataManager Database instance
    ---@param log table Logger
    handle_result = function(task, success, stdout, stderr, data, log)
        local ctx = task.context
        local float = ctx.float

        if not success then
            log.warn("Chart render failed for %s: %s", tostring(float.id), stderr)
            return
        end

        if not task_runner.file_exists(task.output_path) then
            log.warn("Chart render completed but no PNG for %s", tostring(float.id))
            return
        end

        -- Use relative path for LaTeX compatibility
        local png_path = ctx.relative_path or task.output_path
        local json = serialize_result({ png_path = png_path })
        if json then
            float_base.update_resolved_ast(data, float.id, json)
        end
    end
})

return M
