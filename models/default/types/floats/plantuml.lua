---PlantUML type module for SpecCompiler.
---Handles PlantUML diagrams rendering to PNG.
---
---Usage:
---  ```puml:my_diagram
---  @startuml
---  Alice -> Bob: Hello
---  @enduml
---  ```
---
---@module plantuml
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")
local external_render = require("pipeline.transform.external_render_handler")

local M = {}

M.float = {
    id = "PLANTUML",
    long_name = "PlantUML Diagram",
    description = "A PlantUML diagram rendered to PNG",
    caption_format = "Figure",   -- Display as "Figura" in ABNT
    counter_group = "FIGURE",    -- Share counter with FIGURE and CHART
    aliases = { "puml", "plantuml", "uml" },
    needs_external_render = true,
    style_id = "PLANTUML",
}

-- ============================================================================
-- Internal Helpers
-- ============================================================================

local DIAGRAMS_DIR = "diagrams"

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

---Ensures content has @startuml/@enduml wrapper.
---@param content string Raw PlantUML content
---@return string wrapped Content with wrapper added if missing
local function ensure_wrapper(content)
    if not content:match('@startuml') then
        return '@startuml\n' .. content .. '\n@enduml'
    end
    return content
end

---Generates hash for content (for caching).
---@param content string Content to hash
---@return string hash Hash string
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

---Serialize render result to JSON.
---@param result table|nil Render result with png_paths, width, height
---@return string|nil json JSON string or nil
local function serialize_result(result)
    if result and result.png_paths and #result.png_paths > 0 then
        local paths_json = {}
        for _, path in ipairs(result.png_paths) do
            table.insert(paths_json, '"' .. path:gsub('"', '\\"') .. '"')
        end
        local json_parts = { '"png_paths":[' .. table.concat(paths_json, ",") .. ']' }
        if result.width then
            table.insert(json_parts, '"width":"' .. tostring(result.width) .. '"')
        end
        if result.height then
            table.insert(json_parts, '"height":"' .. tostring(result.height) .. '"')
        end
        return '{' .. table.concat(json_parts, ",") .. '}'
    end
    return nil
end

-- ============================================================================
-- External Render Registration
-- ============================================================================

external_render.register_renderer("PLANTUML", {
    ---Prepare a spawn task for this float.
    ---@param float table Float record from database
    ---@param build_dir string Build directory path
    ---@param log table Logger
    ---@return table|nil task Task descriptor or nil to skip
    prepare_task = function(float, build_dir, log)
        local content = ensure_wrapper(float.raw_content or '')
        local hash = hash_content(content)
        local attrs = float_base.decode_attributes(float)

        -- Normalize build_dir to avoid double slashes
        local norm_build_dir = normalize_path(build_dir)
        local diagrams_path = norm_build_dir .. "/" .. DIAGRAMS_DIR
        local puml_file = diagrams_path .. "/" .. hash .. ".puml"
        local png_file = diagrams_path .. "/" .. hash .. ".png"
        -- Store relative path for LaTeX (relative to output file which is in build_dir)
        local relative_png = DIAGRAMS_DIR .. "/" .. hash .. ".png"

        task_runner.ensure_dir(diagrams_path)
        local ok, err = task_runner.write_file(puml_file, content)
        if not ok then
            log.warn("Failed to write puml file: %s", err)
            return nil
        end

        if not task_runner.command_exists("plantuml") then
            log.warn("PlantUML command not found in PATH")
            return nil
        end

        log.debug("Preparing PlantUML: %s", hash:sub(1, 12))

        return {
            -- Force headless mode to avoid X11 dependency in CI/headless environments.
            cmd = "env",
            args = {
                "JAVA_TOOL_OPTIONS=-Djava.awt.headless=true",
                "plantuml",
                "-tpng",
                hash .. ".puml"
            },
            opts = { cwd = diagrams_path, timeout = 30000 },
            output_path = png_file,
            context = {
                hash = hash,
                float = float,
                attrs = attrs,
                diagrams_path = diagrams_path,
                relative_path = relative_png,  -- Path relative to output file (for LaTeX)
                relative_dir = DIAGRAMS_DIR    -- For multi-page outputs
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
            log.warn("PlantUML failed for %s: %s", tostring(float.id), stderr)
            return
        end

        -- Check for multi-page output - use relative paths for LaTeX compatibility
        local png_paths = {}
        if task_runner.file_exists(task.output_path) then
            -- Use relative path for single-page output
            table.insert(png_paths, ctx.relative_path or task.output_path)
        end

        local page = 1
        while true do
            local page_file = string.format("%s/%s_%03d.png", ctx.diagrams_path, ctx.hash, page)
            if task_runner.file_exists(page_file) then
                -- Use relative path for multi-page output
                local relative_page = string.format("%s/%s_%03d.png", ctx.relative_dir or ctx.diagrams_path, ctx.hash, page)
                table.insert(png_paths, relative_page)
                page = page + 1
            else
                break
            end
        end

        if #png_paths == 0 then
            log.warn("PlantUML completed but no PNG for %s", tostring(float.id))
            return
        end

        local result = { png_paths = png_paths }
        if ctx.attrs.width then result.width = ctx.attrs.width end
        if ctx.attrs.height then result.height = ctx.attrs.height end

        local json = serialize_result(result)
        if json then
            float_base.update_resolved_ast(data, float.id, json)
        end
    end
})

-- No M.handler.on_transform - external_render_handler orchestrates

return M
