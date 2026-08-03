---Figure type module for SpecCompiler.
---Handles existing image files (paths to PNG, JPG, etc.).
---
---@module figure
local float_base = require("pipeline.shared.float_base")
local task_runner = require("infra.process.task_runner")

local IMAGES_DIR = "images"

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

---Generates hash for content (for canonical naming, mirrors plantuml.lua).
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

---Copy the resolved image into <build_dir>/images/<content-hash><ext> and
---return the build-relative canonical path (PLANTUML's diagrams/ convention:
---outputs assemble in build_dir, docx emits with --resource-path=build_dir).
---Content-addressed naming: an existing destination has identical bytes by
---construction, so the copy is skipped.
---@param image_path string Resolved source path of the image
---@param build_dir string Build directory path
---@param log table|nil
---@return string|nil relative Canonical path, or nil if the copy failed
local function copy_to_build(image_path, build_dir, log)
    local f = io.open(image_path, "rb")
    if not f then
        if log then log.warn("Figure image not found: %s", image_path) end
        return nil
    end
    local content = f:read("*a")
    f:close()

    local ext = image_path:match("%.[A-Za-z0-9]+$") or ""
    local name = hash_content(content) .. ext
    local images_dir = build_dir:gsub("/+$", ""):gsub("/+", "/") .. "/" .. IMAGES_DIR
    local dest = images_dir .. "/" .. name

    if not task_runner.file_exists(dest) then
        task_runner.ensure_dir(images_dir)
        local ok, err = task_runner.write_file(dest, content)
        if not ok then
            if log then log.warn("Failed to copy figure image %s: %s", image_path, err) end
            return nil
        end
    end
    return IMAGES_DIR .. "/" .. name
end

---TRANSFORM: resolve the figure's image path (relative to its source file),
---copy it into <build_dir>/images/ under a content-hash name, and return the
---png-path JSON the backend image fallback consumes with the build-relative
---canonical path. Falls back to the resolved source path when the image is
---missing or no build_dir is in context. The float resolver's cache key
---includes from_file, so the same path text in different source files
---resolves correctly.
---@param dctx table DATA ctx (subject.raw_content/.float/.build_dir)
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

    local build_dir = dctx.subject.build_dir
    if build_dir then
        image_path = copy_to_build(image_path, build_dir, log) or image_path
    end

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
