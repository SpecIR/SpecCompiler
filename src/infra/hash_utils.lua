-- src/infra/hash_utils.lua
local M = {}

-- Lazy-load pure Lua SHA library (only when pandoc.sha1 unavailable)
local sha2_lib = nil

---Compute SHA1 hash of content
---@param content string Content to hash
---@return string hash 40-character hex string
function M.sha1(content)
    -- Use pandoc's sha1 if available (fastest path when running inside Pandoc)
    if pandoc and pandoc.sha1 then
        return pandoc.sha1(content)
    end

    -- Fallback: use pure Lua SHA1 implementation (for standalone workers)
    if not sha2_lib then
        sha2_lib = require("sha2")
    end
    return sha2_lib.sha1(content)
end

---Compute SHA1 of a file
---@param path string File path
---@return string|nil hash, string|nil error
function M.sha1_file(path)
    local uv = require("luv")
    local stat = uv.fs_stat(path)
    if not stat then
        return nil, "File not found: " .. path
    end

    local fd = uv.fs_open(path, "r", 420)
    if not fd then
        return nil, "Cannot open file: " .. path
    end

    local content = uv.fs_read(fd, stat.size)
    uv.fs_close(fd)

    if not content then
        return nil, "Cannot read file: " .. path
    end

    return M.sha1(content)
end

---Compute hash of P-IR (Pandoc Intermediate Representation) for a specification
---This captures the state of all parsed document data for cache invalidation
---@param data DataManager Data manager instance
---@param spec_id string Specification identifier
---@return string hash 40-character hex string
function M.pir_hash(data, spec_id)
    local parts = {}

    -- Hash spec_objects
    local objects = data:query_all([[
        SELECT id, type_ref, pid, title_text, label, level, start_line, end_line, ast
        FROM spec_objects
        WHERE specification_ref = :spec
        ORDER BY id
    ]], { spec = spec_id })

    for _, obj in ipairs(objects or {}) do
        table.insert(parts, string.format("O:%s:%s:%s:%s:%s:%d:%d:%d:%s",
            tostring(obj.id or ""),
            obj.type_ref or "",
            obj.pid or "",
            obj.title_text or "",
            obj.label or "",
            obj.level or 0,
            obj.start_line or 0,
            obj.end_line or 0,
            obj.ast or ""
        ))
    end

    -- Hash spec_relations
    local relations = data:query_all([[
        SELECT id, type_ref, source_object_id, target_object_id, target_float_id, target_text
        FROM spec_relations
        WHERE specification_ref = :spec
        ORDER BY id
    ]], { spec = spec_id })

    for _, rel in ipairs(relations or {}) do
        table.insert(parts, string.format("R:%s:%s:%s:%s:%s:%s",
            tostring(rel.id or ""),
            rel.type_ref or "",
            tostring(rel.source_object_id or ""),
            tostring(rel.target_object_id or ""),
            tostring(rel.target_float_id or ""),
            rel.target_text or ""
        ))
    end

    -- Hash spec_attribute_values
    local attrs = data:query_all([[
        SELECT av.owner_object_id, av.name, av.raw_value
        FROM spec_attribute_values av
        JOIN spec_objects so ON av.owner_object_id = so.id
        WHERE so.specification_ref = :spec
        ORDER BY av.owner_object_id, av.name
    ]], { spec = spec_id })

    for _, attr in ipairs(attrs or {}) do
        table.insert(parts, string.format("A:%s:%s:%s",
            tostring(attr.owner_object_id or ""),
            attr.name or "",
            attr.raw_value or ""
        ))
    end

    -- Hash spec_floats
    local floats = data:query_all([[
        SELECT id, type_ref, caption, content_sha
        FROM spec_floats
        WHERE specification_ref = :spec
        ORDER BY id
    ]], { spec = spec_id })

    for _, float in ipairs(floats or {}) do
        table.insert(parts, string.format("F:%s:%s:%s:%s",
            tostring(float.id or ""),
            float.type_ref or "",
            float.caption or "",
            float.content_sha or ""
        ))
    end

    -- Combine all parts and hash
    local combined = table.concat(parts, "\n")
    return M.sha1(combined)
end

return M
