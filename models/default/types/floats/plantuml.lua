---PlantUML type module for SpecCompiler.
---Handles PlantUML diagrams rendering to SVG (HTML, clickable links) and
---PNG (DOCX, LaTeX, Markdown).
---
---Usage:
---  ```puml:my_diagram
---  @startuml
---  Alice -> Bob: Hello [REQ-001](@)
---  @enduml
---  ```
---
---CommonSpec links in the source are resolved like Markdown links and
---rewritten to PlantUML's `[[href{tooltip} label]]` syntax before rendering.
---
---@module plantuml
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")

-- ============================================================================
-- Internal Helpers
-- ============================================================================

local DIAGRAMS_DIR = "diagrams"

local is_windows = package.config:sub(1, 1) == "\\"

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

---Serialize a list of paths to a JSON array.
---@param paths string[] Paths
---@return string json JSON array
local function serialize_paths(paths)
    local paths_json = {}
    for _, path in ipairs(paths) do
        table.insert(paths_json, '"' .. path:gsub('"', '\\"') .. '"')
    end
    return '[' .. table.concat(paths_json, ",") .. ']'
end

---Serialize render result to JSON.
---@param result table|nil Render result with png_paths, svg_paths, width, height
---@return string|nil json JSON string or nil
local function serialize_result(result)
    if result and result.png_paths and #result.png_paths > 0 then
        local json_parts = { '"png_paths":' .. serialize_paths(result.png_paths) }
        if result.svg_paths and #result.svg_paths > 0 then
            table.insert(json_parts, '"svg_paths":' .. serialize_paths(result.svg_paths))
        end
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
-- External Render hooks (indexed by the host as float prepare_task/handle_result).
-- These are per-item render hooks, not a phase handler.
-- ============================================================================

return {
    kind = "float",
    schema = {
        id = "PLANTUML",
        long_name = "PlantUML Diagram",
        description = "A PlantUML diagram rendered to SVG and PNG",
        caption_format = "Figure",   -- Display as "Figura" in ABNT
        counter_group = "FIGURE",    -- Share counter with FIGURE and CHART
        aliases = { "puml", "plantuml", "uml" },
        needs_external_render = true,
    },
    hooks = {
        ---Prepare a spawn task for this float.
        ---@param float table Float record from database
        ---@param build_dir string Build directory path
        ---@param log table Logger
        ---@return table|nil task Task descriptor or nil to skip
        prepare_task = function(dctx)
            local float = dctx.subject.float
            local build_dir = dctx.subject.build_dir
            local log = dctx.log
            local content = ensure_wrapper(float.raw_content or '')
            local hash = hash_content(content)
            local attrs = float_base.decode_attributes(float)

            -- Normalize build_dir to avoid double slashes
            local norm_build_dir = normalize_path(build_dir)
            local diagrams_path = norm_build_dir .. "/" .. DIAGRAMS_DIR
            local puml_file = diagrams_path .. "/" .. hash .. ".puml"
            local svg_file = diagrams_path .. "/" .. hash .. ".svg"

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

            -- One PlantUML run emits one format: PNG first, then SVG, so the
            -- SVG (the cache-checked output_path) exists only if both succeeded,
            -- and build dirs from PNG-only versions re-render once.
            -- Force headless mode to avoid X11 dependency in CI/headless environments.
            -- Windows has no `env` and launchers there are .cmd/.bat shims, which
            -- only cmd.exe can run.
            local puml_name = hash .. ".puml"
            local cmd, args = "env", {
                "JAVA_TOOL_OPTIONS=-Djava.awt.headless=true",
                "sh", "-c", 'plantuml -tpng "$1" && plantuml -tsvg "$1"', "sh", puml_name
            }
            if is_windows then
                cmd, args = "cmd", { "/d", "/c", "plantuml", "-tpng", puml_name,
                    "&&", "plantuml", "-tsvg", puml_name }
            end

            return {
                cmd = cmd,
                args = args,
                opts = { cwd = diagrams_path, timeout = 30000 },
                output_path = svg_file,
                context = {
                    hash = hash,
                    float = float,
                    attrs = attrs,
                    diagrams_path = diagrams_path,
                    relative_dir = DIAGRAMS_DIR    -- Paths relative to output file (build_dir)
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
        handle_result = function(dctx)
            local task = dctx.subject.task
            local success = dctx.subject.success
            local stderr = dctx.subject.stderr
            local data = dctx.data
            local log = dctx.log
            local ctx = task.context
            local float = ctx.float

            if not success then
                log.warn("PlantUML failed for %s: %s", tostring(float.id), stderr)
                return
            end

            -- Single-page output is <hash>.<ext>; multi-page adds <hash>_NNN.<ext>.
            -- Paths are stored relative to the output file (build_dir).
            local relative_dir = ctx.relative_dir or ctx.diagrams_path
            local function collect(ext)
                local paths = {}
                local single = string.format("%s/%s.%s", ctx.diagrams_path, ctx.hash, ext)
                if task_runner.file_exists(single) then
                    table.insert(paths, string.format("%s/%s.%s", relative_dir, ctx.hash, ext))
                end
                local page = 1
                while task_runner.file_exists(string.format("%s/%s_%03d.%s", ctx.diagrams_path, ctx.hash, page, ext)) do
                    table.insert(paths, string.format("%s/%s_%03d.%s", relative_dir, ctx.hash, page, ext))
                    page = page + 1
                end
                return paths
            end

            local png_paths = collect("png")
            -- A model overriding only prepare_task (PNG-only, PNG output_path)
            -- keeps working with this handler
            if #png_paths == 0 and task.output_path:match("%.png$")
                    and task_runner.file_exists(task.output_path) then
                png_paths = { ctx.relative_path or task.output_path }
            end
            if #png_paths == 0 then
                log.warn("PlantUML completed but no PNG for %s", tostring(float.id))
                return
            end

            local result = { png_paths = png_paths, svg_paths = collect("svg") }
            if ctx.attrs.width then result.width = ctx.attrs.width end
            if ctx.attrs.height then result.height = ctx.attrs.height end

            local json = serialize_result(result)
            if json then
                float_base.update_resolved_ast(data, float.id, json)
            end
        end,

        ---Format a resolved CommonSpec link in PlantUML hyperlink syntax.
        ---Brackets and braces would end the link early, so they are dropped
        ---from the label and tooltip; backslashes start PlantUML escapes
        ---(\n, \t), so they become slashes. The URL ends at the first space,
        ---so spaces in it (a spec file name with a space) are percent-encoded.
        ---@param dctx table Hook context: subject.href, subject.display_text
        ---@return string link PlantUML `[[href{tooltip} label]]`
        format_link = function(dctx)
            local text = dctx.subject.display_text:gsub("[%[%]{}]", ""):gsub("\\", "/")
            local href = dctx.subject.href:gsub(" ", "%%20")
            return string.format("[[%s{%s} %s]]", href, text, text)
        end,

        ---Blank out PlantUML comments (`' line` and `/' block '/`) so links in
        ---them are not registered, as Markdown ignores links in HTML comments.
        ---Newlines are kept so link line numbers stay exact.
        ---@param dctx table Hook context: subject.raw_content
        ---@return string text Source with comment characters replaced by spaces
        mask_comments = function(dctx)
            local function blank(s) return (s:gsub("[^\n]", " ")) end
            local text = dctx.subject.raw_content:gsub("/'.-'/", blank)
            return (text:gsub("[^\n]+", function(line)
                if line:match("^%s*'") then return blank(line) end
            end))
        end
    }
}
