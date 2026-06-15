---Spec Object Base utilities for SpecCompiler.
---Shared infrastructure for spec object type handlers.
---
---Provides:
---  - Styled headers with PID prefix (e.g., "HLR-001: Title")
---  - Attribute display as DefinitionList
---  - card_render: the host-owned standard object-card renderer (registered on
---    the TRACEABLE base type; leaf types inherit it and stay pure schema)
---
---@module spec_object_base
local M = {}

local render_utils = require("pipeline.shared.render_utils")
local ast_utils = require("pipeline.shared.ast_utils")

-- ============================================================================
-- Utilities
-- ============================================================================

---Format attribute name for display (title case).
---@param name string Attribute name (e.g., "verification_method")
---@return string formatted Formatted name (e.g., "Verification Method")
local function format_attr_name(name)
    if not name then return "" end
    -- Replace underscores with spaces and capitalize words
    return name:gsub("_", " "):gsub("(%a)([%w]*)", function(first, rest)
        return first:upper() .. rest:lower()
    end)
end

---Get sorted keys from a table.
---@param t table
---@return table keys Sorted array of keys
local function get_sorted_keys(t)
    local keys = {}
    for k in pairs(t) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

-- ============================================================================
-- Default Rendering Functions
-- ============================================================================

---Default header rendering for spec objects.
---Renders: "PID: Title" with a semantic spec-object custom style.
---@param ctx table Render context (spec_object, header_level, attributes, etc.)
---@param pandoc table Pandoc module
---@param options table|nil Optional configuration {show_pid, unnumbered}
---@return table Pandoc Header element
function M.header(ctx, pandoc, options)
    options = options or {}
    local obj = ctx.spec_object
    local pid = obj.pid or ""
    local title = obj.title_text or ""
    local type_ref = obj.type_ref or ""

    -- show_pid defaults to true (backward compatible)
    local show_pid = options.show_pid ~= false

    -- Build header text: "PID: Title" or just "Title" when show_pid is false
    local header_content = {}

    if show_pid and pid ~= "" then
        table.insert(header_content, pandoc.Str(pid))
        if title ~= "" then
            table.insert(header_content, pandoc.Str(": "))
        end
    end

    if title ~= "" then
        table.insert(header_content, pandoc.Str(title))
    end

    -- If no PID and no title, use type as fallback
    if #header_content == 0 then
        table.insert(header_content, pandoc.Str(type_ref))
    end

    -- Create header with appropriate level.
    -- Shift by -1 for consistency with section.lua: markdown ## (level 2) becomes
    -- Heading 1 in DOCX, since the H1 document title is rendered as a Div.
    local level = math.max((ctx.header_level or 2) - 1, 1)
    local header = pandoc.Header(level, header_content)

    -- Apply a semantic custom style. DOCX converts this wrapper into a
    -- SpecObjectHeader paragraph instead of reusing Heading1-5.
    -- Set id to PID for anchor linking.
    local style = "SpecObjectHeader"
    local anchor_id = pid ~= "" and pid or ""

    -- Spec objects use PIDs as identifiers, so section numbering is redundant.
    -- Default unnumbered=true; types can opt back in with unnumbered=false.
    local classes = {}
    if options.unnumbered ~= false then
        table.insert(classes, "unnumbered")
    end

    header.attr = pandoc.Attr(anchor_id, classes, {["custom-style"] = style})

    return header
end

---Render attributes as a DefinitionList.
---@param ctx table Render context with attributes
---@param pandoc table Pandoc module
---@param attr_order table|nil Optional array of attribute names in display order
---@return table|nil Pandoc Div containing DefinitionList, or nil if no attributes
function M.render_attributes(ctx, pandoc, attr_order)
    local attrs = ctx.attributes or {}
    local items = {}
    local rendered = {}  -- Track which attributes we've rendered

    -- Helper to add an attribute item
    local function add_item(name)
        local attr_data = attrs[name] or {}
        local value = attr_data.value
        local ast_json = attr_data.ast

        if value and value ~= "" and not rendered[name] then
            -- Format name: "status" -> "STATUS", make it bold
            local term_text = format_attr_name(name):upper()
            local term = {pandoc.Strong{pandoc.Str(term_text .. ":")}}

            -- Try to use AST for rich content (links, formatting)
            local def_content
            local ast_content, content_type = ast_utils.decode_with_type(ast_json)
            if ast_content and #ast_content > 0 then
                if content_type == "blocks" then
                    -- Multi-block content (Para, BulletList, etc.) - use directly
                    def_content = ast_content
                else
                    -- Inline content - wrap in Plain
                    def_content = {pandoc.Plain(ast_content)}
                end
            else
                def_content = {pandoc.Plain{pandoc.Str(tostring(value))}}
            end

            table.insert(items, {term, {def_content}})
            rendered[name] = true
        end
    end

    -- First, render attributes in specified order
    if attr_order then
        for _, name in ipairs(attr_order) do
            add_item(name)
        end
    end

    -- Then, render any remaining attributes alphabetically
    local remaining = get_sorted_keys(attrs)
    for _, name in ipairs(remaining) do
        add_item(name)  -- Will skip if already rendered
    end

    if #items == 0 then
        return nil
    end

    local dl = pandoc.DefinitionList(items)
    local div = pandoc.Div({dl}, pandoc.Attr("", {"spec-object-attributes"}, {
        ["custom-style"] = "SpecObjectAttributes"
    }))

    return div
end

---Default body rendering for spec objects.
---Renders original content followed by attributes.
---@param ctx table Render context
---@param pandoc table Pandoc module
---@param options table|nil Optional configuration {attr_order, skip_attributes, attrs_first}
---@return table Array of Pandoc blocks
function M.body(ctx, pandoc, options)
    options = options or {}
    local blocks = {}

    -- Include original content blocks first (the body/description text)
    local original_blocks = ctx.original_blocks or {}
    local body_blocks = {}
    for _, block in ipairs(original_blocks) do
        table.insert(body_blocks, block)
    end

    -- Wrap body content in SpecObjectBody styled Div for custom indent
    if #body_blocks > 0 then
        local body_div = pandoc.Div(body_blocks, pandoc.Attr("", {"spec-object-body"}, {
            ["custom-style"] = "SpecObjectBody"
        }))
        table.insert(blocks, body_div)
    end

    -- Render attributes after body content
    if not options.skip_attributes then
        local attr_block = M.render_attributes(ctx, pandoc, options.attr_order)
        if attr_block then
            table.insert(blocks, attr_block)
        end
    end

    return blocks
end

---The host-owned standard object-card renderer: header + attributes wrapped in a
---`spec-object` Div. It is registered as the render hook of the base requirement
---type (TRACEABLE); every leaf requirement type inherits it through the host's
---extends-chain dispatch and declares its render options as plain SCHEMA fields
---(show_pid/unnumbered/skip_attributes/attr_order), read here from the rendering
---type's schema (ctx.subject.type_schema). A type wanting a non-standard render
---declares its own hooks.render instead (e.g. COVER).
---@param ctx table canonical ctx (subject.object/type_schema/attributes/element)
---@return table[] blocks
function M.card_render(ctx)
    local subject = ctx.subject
    local obj = subject.object
    -- The rendering type's schema doubles as the declarative render-option set;
    -- M.header/M.body read only their option keys (no collision with schema
    -- structural fields).
    local options = subject.type_schema or {}

    local render_ctx = {
        spec_object = obj,
        header_level = subject.header_level or (obj and obj.level) or 2,
        attributes = subject.attributes or {},
        original_blocks = subject.element or {},
        output_format = ctx.format,
        spec_id = ctx.spec_id,
    }

    local blocks = {}
    render_utils.add_header_blocks(blocks, M.header(render_ctx, ctx.pandoc, options))
    render_utils.add_blocks(blocks, M.body(render_ctx, ctx.pandoc, options))

    local wrapper = ctx.pandoc.Div(blocks, ctx.pandoc.Attr("", {"spec-object"}, {}))
    return { wrapper }
end

return M
