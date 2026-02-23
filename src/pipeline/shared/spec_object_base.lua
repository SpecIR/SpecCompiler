---Spec Object Base utilities for SpecCompiler.
---Shared infrastructure for spec object type handlers.
---
---Provides:
---  - Styled headers with PID prefix (e.g., "HLR-001: Title")
---  - Attribute display as DefinitionList
---  - Extensible rendering via create_handler()
---
---@module spec_object_base
local M = {}

local render_utils = require("pipeline.shared.render_utils")

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
---Renders: "PID: Title" with type-specific custom-style.
---@param ctx table Render context (spec_object, header_level, attributes, etc.)
---@param pandoc table Pandoc module
---@param db DataManager Database manager
---@param options table|nil Optional configuration {show_pid, unnumbered}
---@return table Pandoc Header element
function M.header(ctx, pandoc, db, options)
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

    -- Create header with appropriate level
    local level = ctx.header_level or 2
    local header = pandoc.Header(level, header_content)

    -- Apply custom-style based on type (e.g., "HLRHeader", "LLRHeader")
    -- Set id to PID for anchor linking
    local style = type_ref .. "Header"
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
---@param db DataManager Database manager
---@param attr_order table|nil Optional array of attribute names in display order
---@return table|nil Pandoc Div containing DefinitionList, or nil if no attributes
function M.render_attributes(ctx, pandoc, db, attr_order)
    local attrs = ctx.attributes or {}
    local items = {}
    local rendered = {}  -- Track which attributes we've rendered

    -- Helper to decode AST JSON to Pandoc content (inlines or blocks)
    local function decode_ast(ast_json)
        if not ast_json or ast_json == "" then return nil, nil end
        local result = pandoc.json.decode(ast_json)
        if result and type(result) == "table" and #result > 0 then
            -- Check if result contains blocks (Para, Plain, etc.) or inlines
            local first = result[1]
            if first and first.t and (first.t == "Para" or first.t == "Plain" or first.t == "BulletList") then
                -- Multi-block content
                return result, "blocks"
            else
                -- Array of inlines
                return result, "inlines"
            end
        end
        return nil, nil
    end

    -- Helper to add an attribute item
    local function add_item(name)
        local attr_data = attrs[name]
        -- Handle both old format (string) and new format ({value, ast})
        local value, ast_json
        if type(attr_data) == "table" then
            value = attr_data.value
            ast_json = attr_data.ast
        else
            value = attr_data
        end

        if value and value ~= "" and not rendered[name] then
            -- Format name: "status" -> "STATUS", make it bold
            local term_text = format_attr_name(name):upper()
            local term = {pandoc.Strong{pandoc.Str(term_text .. ":")}}

            -- Try to use AST for rich content (links, formatting)
            local def_content
            local ast_content, content_type = decode_ast(ast_json)
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
---@param db DataManager Database manager
---@param options table|nil Optional configuration {attr_order, skip_attributes, attrs_first}
---@return table Array of Pandoc blocks
function M.body(ctx, pandoc, db, options)
    options = options or {}
    local blocks = {}

    -- Include original content blocks first (the body/description text)
    local original_blocks = ctx.original_blocks or {}
    for _, block in ipairs(original_blocks) do
        table.insert(blocks, block)
    end

    -- Render attributes after body content
    if not options.skip_attributes then
        local attr_block = M.render_attributes(ctx, pandoc, db, options.attr_order)
        if attr_block then
            table.insert(blocks, attr_block)
        end
    end

    return blocks
end

-- ============================================================================
-- Handler Factory
-- ============================================================================

---Create a handler for a spec object type.
---Supports customization via options table.
---
---Options:
---  - attr_order: array of attribute names in display order
---  - skip_attributes: boolean to skip attribute rendering
---  - unnumbered: boolean to exclude from section numbering (default true)
---  - show_pid: boolean to show PID in header (default true)
---  - header: custom header function(ctx, pandoc, db)
---  - body: custom body function(ctx, pandoc, db)
---  - body_extension: function(ctx, pandoc, db) returning additional blocks
---  - prerequisites: array of prerequisite handler names
---
---@param name string Handler name
---@param options table|nil Customization options
---@return table Handler module with on_render_SpecObject
function M.create_handler(name, options)
    options = options or {}

    local handler = {
        name = name,
        prerequisites = options.prerequisites or {},
    }

    -- Build the header render function
    local header_fn
    if options.header then
        header_fn = options.header
    else
        header_fn = function(ctx, p, db)
            return M.header(ctx, p, db, options)
        end
    end

    -- Build the body render function
    local body_fn
    if options.body then
        body_fn = options.body
    else
        body_fn = function(ctx, p, db)
            local blocks = M.body(ctx, p, db, options)

            -- Add extension blocks if provided
            if options.body_extension then
                local extra = options.body_extension(ctx, p, db)
                if extra then
                    if extra.t then
                        -- Single block
                        table.insert(blocks, extra)
                    else
                        -- Array of blocks
                        for _, b in ipairs(extra) do
                            table.insert(blocks, b)
                        end
                    end
                end
            end

            return blocks
        end
    end

    -- Create on_render_SpecObject directly instead of using base_handler
    function handler.on_render_SpecObject(obj, ctx)
        local blocks = {}

        -- Build render context for header/body functions
        local render_ctx = {
            spec_object = obj,
            header_level = ctx.header_level or obj.level or 2,
            attributes = ctx.attributes or {},
            original_blocks = ctx.original_blocks or {},
            output_format = ctx.output_format or "docx",
            spec_id = ctx.spec_id or "default",
            db = ctx.db,
            api = ctx.api,
        }

        -- Call header function
        local header_result = header_fn(render_ctx, pandoc, ctx.db)
        render_utils.add_header_blocks(blocks, header_result)

        -- Call body function
        local body_result = body_fn(render_ctx, pandoc, ctx.db)
        render_utils.add_blocks(blocks, body_result)

        -- Wrap in spec-object container for HTML card styling.
        -- Other formats (DOCX) treat the Div as transparent.
        local wrapper = pandoc.Div(blocks, pandoc.Attr("", {"spec-object"}, {}))
        return {wrapper}
    end

    return handler
end

return M
