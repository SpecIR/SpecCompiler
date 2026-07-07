---Label utilities for SpecCompiler.
---Generates unified labels for spec_objects and spec_floats.
---Label format: {type_prefix_lower}:{title_slug}
---
---@module label_utils
local M = {}

-- UTF-8 → ASCII transliteration for Latin accented letters (both cases map
-- to lowercase, since slugs are lowercase). Sequences not in this table are
-- stripped, matching the previous byte-strip behavior for non-Latin scripts.
local TRANSLIT = {
    ["à"]="a", ["á"]="a", ["â"]="a", ["ã"]="a", ["ä"]="a", ["å"]="a",
    ["À"]="a", ["Á"]="a", ["Â"]="a", ["Ã"]="a", ["Ä"]="a", ["Å"]="a",
    ["ç"]="c", ["Ç"]="c",
    ["è"]="e", ["é"]="e", ["ê"]="e", ["ë"]="e",
    ["È"]="e", ["É"]="e", ["Ê"]="e", ["Ë"]="e",
    ["ì"]="i", ["í"]="i", ["î"]="i", ["ï"]="i",
    ["Ì"]="i", ["Í"]="i", ["Î"]="i", ["Ï"]="i",
    ["ñ"]="n", ["Ñ"]="n",
    ["ò"]="o", ["ó"]="o", ["ô"]="o", ["õ"]="o", ["ö"]="o", ["ø"]="o",
    ["Ò"]="o", ["Ó"]="o", ["Ô"]="o", ["Õ"]="o", ["Ö"]="o", ["Ø"]="o",
    ["ù"]="u", ["ú"]="u", ["û"]="u", ["ü"]="u",
    ["Ù"]="u", ["Ú"]="u", ["Û"]="u", ["Ü"]="u",
    ["ý"]="y", ["ÿ"]="y", ["Ý"]="y",
    ["ß"]="ss", ["æ"]="ae", ["Æ"]="ae", ["œ"]="oe", ["Œ"]="oe",
    ["ð"]="d", ["Ð"]="d", ["þ"]="th", ["Þ"]="th",
}

---Slugify text into a URL/anchor-safe format.
---Transliterates Latin accented letters to ASCII (ç→c, á→a), lowercases,
---replaces non-alphanumeric characters with hyphens, collapses consecutive
---hyphens, trims leading/trailing hyphens.
---@param text string The text to slugify
---@return string slug The slugified text
function M.slugify(text)
    if not text or text == "" then
        return ""
    end
    -- Transliterate or strip each multi-byte UTF-8 sequence in one pass
    local slug = text:gsub("[\xC2-\xF4][\x80-\xBF]*", function(seq)
        return TRANSLIT[seq] or ""
    end)
    slug = slug:lower()
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
