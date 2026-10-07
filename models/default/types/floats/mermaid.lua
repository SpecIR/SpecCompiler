---Mermaid type module for SpecCompiler.
---Handles Mermaid diagrams rendering to PNG via the mermaid-cli (`mmdc`).
---
---Usage:
---  ```mermaid:my_diagram
---  sequenceDiagram
---      Alice->>Bob: Hello
---  ```
---
---@module mermaid
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
    path = path:gsub("/+$", "")
    path = path:gsub("/+", "/")
    return path
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
---@param result table Render result with png_path, width, height
---@return string json JSON string
local function serialize_result(result)
    local parts = { '"png_paths":["' .. result.png_path:gsub('"', '\\"') .. '"]' }
    if result.width then
        table.insert(parts, '"width":"' .. tostring(result.width) .. '"')
    end
    if result.height then
        table.insert(parts, '"height":"' .. tostring(result.height) .. '"')
    end
    return '{' .. table.concat(parts, ",") .. '}'
end

-- ============================================================================
-- External Render hooks (indexed by the host as float prepare_task/handle_result).
-- ============================================================================

return {
    kind = "float",
    schema = {
        id = "MERMAID",
        long_name = "Mermaid Diagram",
        description = "A Mermaid diagram rendered to PNG",
        caption_format = "Figure",
        counter_group = "FIGURE",    -- Share counter with FIGURE and PLANTUML
        aliases = { "mermaid", "mmd" },
        needs_external_render = true,
    },
    hooks = {
        ---Prepare a spawn task for this float.
        ---@param dctx table Hook context: subject.float, subject.build_dir, log
        ---@return table|nil task Task descriptor or nil to skip
        prepare_task = function(dctx)
            local float = dctx.subject.float
            local build_dir = dctx.subject.build_dir
            local log = dctx.log
            local content = float.raw_content or ''
            local hash = hash_content(content)
            local attrs = float_base.decode_attributes(float)

            local diagrams_path = normalize_path(build_dir) .. "/" .. DIAGRAMS_DIR
            local mmd_file = diagrams_path .. "/" .. hash .. ".mmd"
            local png_file = diagrams_path .. "/" .. hash .. ".png"
            -- Path relative to the output file (which lives in build_dir)
            local relative_png = DIAGRAMS_DIR .. "/" .. hash .. ".png"

            task_runner.ensure_dir(diagrams_path)
            local ok, err = task_runner.write_file(mmd_file, content)
            if not ok then
                log.warn("Failed to write mmd file: %s", err)
                return nil
            end

            if not task_runner.command_exists("mmdc") then
                log.warn("Mermaid CLI (mmdc) not found in PATH")
                return nil
            end

            log.debug("Preparing Mermaid: %s", hash:sub(1, 12))

            -- npm installs `mmdc` as a .cmd shim on Windows, which only cmd.exe can run.
            local cmd, args = "mmdc", { "-i", hash .. ".mmd", "-o", hash .. ".png" }
            if is_windows then
                cmd, args = "cmd", { "/d", "/c", "mmdc", "-i", hash .. ".mmd", "-o", hash .. ".png" }
            end

            return {
                cmd = cmd,
                args = args,
                opts = { cwd = diagrams_path, timeout = 60000 },
                output_path = png_file,
                context = {
                    float = float,
                    attrs = attrs,
                    relative_path = relative_png,
                }
            }
        end,

        ---Handle result after spawn completes.
        ---@param dctx table Hook context: subject.task/success/stderr, data, log
        handle_result = function(dctx)
            local task = dctx.subject.task
            local success = dctx.subject.success
            local stderr = dctx.subject.stderr
            local data = dctx.data
            local log = dctx.log
            local ctx = task.context
            local float = ctx.float

            if not success then
                log.warn("Mermaid failed for %s: %s", tostring(float.id), stderr)
                return
            end

            if not task_runner.file_exists(task.output_path) then
                log.warn("Mermaid completed but no PNG for %s", tostring(float.id))
                return
            end

            local result = { png_path = ctx.relative_path }
            if ctx.attrs.width then result.width = ctx.attrs.width end
            if ctx.attrs.height then result.height = ctx.attrs.height end

            float_base.update_resolved_ast(data, float.id, serialize_result(result))
        end
    }
}
