---Label utilities for SpecCompiler.
---Generates unified labels for spec_objects and spec_floats.
---Label format: {type_prefix_lower}:{title_slug}
---
---@module label_utils
local M = {}

---Slugify text into a URL/anchor-safe format.
---Lowercases, replaces non-alphanumeric characters with hyphens,
---collapses consecutive hyphens, trims leading/trailing hyphens.
---@param text string The text to slugify
---@return string slug The slugified text
function M.slugify(text)
    if not text or text == "" then
        return ""
    end
    local slug = text:lower()
    slug = slug:gsub("[^%w%s%-]", "") -- remove non-alphanumeric except spaces and hyphens
    slug = slug:gsub("%s+", "-")       -- spaces to hyphens
    slug = slug:gsub("%-+", "-")       -- collapse consecutive hyphens
    slug = slug:gsub("^%-", "")        -- trim leading hyphen
    slug = slug:gsub("%-$", "")        -- trim trailing hyphen
    return slug
end

---Compute a label for a spec_object.
---Format: {type_prefix_lower}:{title_slug}
---Examples:
---  compute_object_label("HLR", "Do Something") → "hlr:do-something"
---  compute_object_label("SECTION", "Introduction") → "section:introduction"
---  compute_object_label(nil, "My Title") → "obj:my-title"
---@param type_ref string|nil The object type identifier (e.g., "HLR", "SECTION")
---@param title_text string The object title text (must be non-empty)
---@return string|nil label The computed label, or nil if title is empty
function M.compute_object_label(type_ref, title_text)
    if not title_text or title_text:match("^%s*$") then
        return nil
    end
    local prefix = type_ref and type_ref:lower() or "obj"
    local slug = M.slugify(title_text)
    if slug == "" then
        return nil
    end
    return prefix .. ":" .. slug
end

---Compute a label for a spec_float.
---Format: {type_prefix_lower}:{user_label}
---Examples:
---  compute_float_label("fig", "architecture") → "fig:architecture"
---  compute_float_label("tbl", "data-summary") → "tbl:data-summary"
---@param type_prefix string The type prefix (e.g., "fig", "tbl", "src")
---@param user_label string The user-defined label from code block syntax
---@return string label The computed label
function M.compute_float_label(type_prefix, user_label)
    local prefix = type_prefix and type_prefix:lower() or "unk"
    local label = user_label or ""
    return prefix .. ":" .. label
end

---Make a label unique by appending a numeric suffix if collision detected.
---Follows Pandoc convention: base, base-1, base-2, etc.
---@param base_label string The base label to make unique
---@param existing_labels table Set of existing labels (label → true)
---@return string unique_label A label not present in existing_labels
function M.make_unique_label(base_label, existing_labels)
    if not existing_labels[base_label] then
        return base_label
    end
    local suffix = 1
    while true do
        local candidate = base_label .. "-" .. suffix
        if not existing_labels[candidate] then
            return candidate
        end
        suffix = suffix + 1
    end
end

return M
