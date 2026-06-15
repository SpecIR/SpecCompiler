---Figure type module for SpecCompiler.
---Handles existing image files (paths to PNG, JPG, etc.).
---
---@module figure
local float_base = require("pipeline.shared.float_base")

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

---TRANSFORM: resolve the figure's image path (relative to its source file) and
---return the png-path JSON the backend image fallback consumes. The float
---resolver's cache key includes from_file, so the same path text in different
---source files resolves correctly.
---@param raw_content string The raw image path from the figure block
---@param float table Float record (reads from_file + attributes)
---@param log table|nil
---@return string|nil resolved png-path JSON, or nil on empty path
local function transform(dctx)
    local raw_content = dctx.subject.raw_content
    local float = dctx.subject.float
    local log = dctx.log
    local raw_image_path = (raw_content or ""):match("^%s*(.-)%s*$")  -- trim
    if raw_image_path == "" then
        if log then log.warn("Figure has empty image path") end
        return nil
    end

    local attrs = float_base.decode_attributes(float)
    local image_path = resolve_image_path(raw_image_path, float.from_file or "")

    -- Note: backend expects "png_path" key for image floats
    local resolved = {
        png_path = image_path,
        width = attrs.width,
        height = attrs.height,
        source = attrs.source,
    }

    if pandoc and pandoc.json and pandoc.json.encode then
        return pandoc.json.encode(resolved)
    end
    return string.format(
        '{"png_path":"%s","width":%s,"height":%s,"source":%s}',
        image_path:gsub('"', '\\"'),
        attrs.width and ('"' .. attrs.width .. '"') or "null",
        attrs.height and ('"' .. attrs.height .. '"') or "null",
        resolved.source and ('"' .. resolved.source:gsub('"', '\\"') .. '"') or "null"
    )
end

-- FIGURE renders via the backend image fallback (no render hook); its only hook
-- is the TRANSFORM resolution of the image path.
return {
    kind = "float",
    schema = {
        id = "FIGURE",
        long_name = "Figure",
        description = "An image or illustration (existing image path)",
        caption_format = "Figure",
        counter_group = "FIGURE",  -- Shared counter for all figure-like floats
        aliases = { "fig", "image" },
        needs_external_render = false,
    },
    hooks = { transform = transform },
}
