---Native Pandoc Lua filter for Markdown output.
---Transforms speccompiler format markers to markdown-compatible output.
---
---This filter is compatible with pandoc --lua-filter for external CLI execution.
---
---Features:
---  - Converts RawBlock("speccompiler", "page-break") to horizontal rule
---  - Removes RawBlock("speccompiler", "vertical-space:NNNN") - no markdown equivalent
---  - Removes other speccompiler markers that have no markdown equivalent
---
---@usage pandoc --lua-filter=markdown.lua -f json -t markdown input.json
---@module models.default.filters.markdown
-- ============================================================================
-- Marker Parsing
-- ============================================================================

---Parse a speccompiler marker text.
---@param text string Marker text (e.g., "page-break", "vertical-space:1440")
---@return string marker_type Type of marker
---@return string|nil value Optional value for parameterized markers
local function parse_marker(text)
    local marker_type, value = text:match("^([^:]+):?(.*)$")
    if value == "" then
        value = nil
    end
    return marker_type, value
end

-- ============================================================================
-- RawBlock Handler
-- ============================================================================

---Convert a speccompiler RawBlock to markdown.
---@param block pandoc.RawBlock The block to convert
---@return pandoc.Block|nil Converted block, or nil to remove
local function convert_speccompiler_block(block)
    local marker_type, _ = parse_marker(block.text)

    if marker_type == "page-break" then
        -- Markdown has no page break concept - insert horizontal rule
        return pandoc.HorizontalRule()

    elseif marker_type == "vertical-space" then
        -- Markdown has no vertical spacing - remove
        return {}

    else
        -- Unknown speccompiler marker - remove
        return {}
    end
end

-- ============================================================================
-- Link Extension Replacement
-- ============================================================================

---Replace .ext placeholder with .md in cross-document links.
---@param link pandoc.Link The link to process
---@return pandoc.Link Modified link
local function replace_ext_placeholder(link)
    if link.target then
        link.target = link.target:gsub("%.ext#", ".md#")
        link.target = link.target:gsub("%.ext$", ".md")
    end
    return link
end

-- ============================================================================
-- Native Pandoc Filter Table
-- Pandoc expects an array of filter tables for the traversal
-- ============================================================================

return {{
    RawBlock = function(block)
        if block.format == "speccompiler" then
            return convert_speccompiler_block(block)
        end
        -- Pass through other RawBlocks unchanged
        return block
    end,

    Link = function(link)
        return replace_ext_placeholder(link)
    end
}}
