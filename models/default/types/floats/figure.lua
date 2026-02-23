---Figure type module for SpecCompiler.
---Handles existing image files (paths to PNG, JPG, etc.).
---
---@module figure
local float_base = require("pipeline.shared.float_base")

local M = {}

M.float = {
    id = "FIGURE",
    long_name = "Figure",
    description = "An image or illustration (existing image path)",
    caption_format = "Figure",
    counter_group = "FIGURE",  -- Shared counter for all figure-like floats
    aliases = { "fig", "image" },
    needs_external_render = false,
    style_id = "FIGURE",
}

-- ============================================================================
-- Handler
-- ============================================================================

---Resolve image path relative to source file.
---@param image_path string The raw path from the figure block
---@param from_file string The source file where the figure was defined
---@return string resolved_path The resolved path
local function resolve_image_path(image_path, from_file)
    -- If already absolute, return as-is
    if image_path:match("^/") then
        return image_path
    end

    -- Get directory of source file
    local source_dir = from_file:match("^(.*/)[^/]*$") or ""

    -- Resolve relative to source directory
    return source_dir .. image_path
end

M.handler = {
    name = "figure_handler",
    prerequisites = {},  -- Runs in TRANSFORM phase

    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local log = float_base.create_log(diagnostics)
            local floats = float_base.query_floats_by_type(data, ctx, "FIGURE")

            for _, float in ipairs(floats or {}) do
                local attrs = float_base.decode_attributes(float)
                local raw_image_path = (float.raw_content or ""):match("^%s*(.-)%s*$")  -- trim

                if raw_image_path ~= "" then
                    -- Resolve path relative to source file
                    local image_path = resolve_image_path(raw_image_path, float.from_file or "")

                    -- Store resolved path with attributes as JSON
                    -- Note: backend expects "png_path" key for image floats
                    local resolved = {
                        png_path = image_path,
                        width = attrs.width,
                        height = attrs.height,
                        source = attrs.source,
                    }

                    local resolved_json
                    if pandoc and pandoc.json and pandoc.json.encode then
                        resolved_json = pandoc.json.encode(resolved)
                    else
                        resolved_json = string.format(
                            '{"png_path":"%s","width":%s,"height":%s,"source":%s}',
                            image_path:gsub('"', '\\"'),
                            attrs.width and ('"' .. attrs.width .. '"') or "null",
                            attrs.height and ('"' .. attrs.height .. '"') or "null",
                            resolved.source and ('"' .. resolved.source:gsub('"', '\\"') .. '"') or "null"
                        )
                    end

                    float_base.update_resolved_ast(data, float.id, resolved_json)
                    log.debug("Figure resolved: %s -> %s", tostring(float.id), image_path)
                else
                    log.warn("Figure %s has empty image path", tostring(float.id))
                end
            end
        end
    end
}

return M
