---Float Base utilities for SpecCompiler.
---Shared infrastructure for float type handlers.
---
---@module float_base
local Queries = require("db.queries")

local M = {}

---Update resolved_ast for a float in the database.
---@param data DataManager
---@param identifier string Float identifier
---@param result_json string JSON string to store
function M.update_resolved_ast(data, identifier, result_json)
    data:execute(Queries.content.update_float_resolved,
        { id = identifier, ast = result_json })
end

---Query all floats of a specific type for a specification.
---@param data DataManager
---@param ctx Context
---@param type_ref string Type reference (e.g., "FIGURE", "TABLE")
---@return table|nil floats Array of float records
function M.query_floats_by_type(data, ctx, type_ref)
    local spec_id = ctx.spec_id or "default"
    return data:query_all(Queries.content.select_floats_by_type,
        { type_ref = type_ref, spec_id = spec_id })
end

---Query floats by multiple type references.
---@param data DataManager
---@param ctx Context
---@param type_refs table Array of type references
---@return table|nil floats Array of float records
function M.query_floats_by_types(data, ctx, type_refs)
    local spec_id = ctx.spec_id or "default"
    local sql, params = Queries.content.build_floats_by_types(type_refs)
    params.spec_id = spec_id
    return data:query_all(sql, params)
end

---Decode attributes JSON from a float record.
---@param float table Float record with pandoc_attributes field
---@return table attrs Decoded attributes (empty table if none)
function M.decode_attributes(float)
    if not float or not float.pandoc_attributes then
        return {}
    end

    local attrs = pandoc.json.decode(float.pandoc_attributes)
    if type(attrs) == "table" then
        return attrs
    end

    return {}
end

---Create a logger wrapper from diagnostics.
---Routes debug/info to operational logs, warn/error to diagnostics (if available) or logger.
---@param diagnostics Diagnostics|nil
---@return table log Logger with debug/error/info/warn methods
function M.create_log(diagnostics)
    local logger = require("infra.logger")
    return {
        debug = function(fmt, ...)
            local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
            logger.log("debug", msg)
        end,
        info = function(fmt, ...)
            local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
            logger.log("info", msg)
        end,
        warn = function(fmt, ...)
            local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
            if diagnostics then
                diagnostics:warn(nil, nil, "FLOAT", msg)
            else
                logger.diagnostic("warning", msg)
            end
        end,
        error = function(fmt, ...)
            local msg = select("#", ...) > 0 and string.format(fmt, ...) or tostring(fmt)
            if diagnostics then
                diagnostics:error(nil, nil, "FLOAT", msg)
            else
                logger.diagnostic("error", msg)
            end
        end
    }
end

---Serialize Pandoc AST to JSON-like string for storage.
---@param ast table Pandoc AST element
---@return string|nil JSON-like string
function M.serialize_ast(ast)
    if not ast then return nil end

    -- For simple cases, use Pandoc's built-in JSON writer if available
    if pandoc and pandoc.write then
        local ok, json = pcall(function()
            return pandoc.write(pandoc.Pandoc({ast}), 'json')
        end)
        if ok then return json end
    end

    -- Fallback: just return a marker that content was resolved
    return '{"resolved": true}'
end

-- ============================================================================
-- Source/Caption Decoration (format-agnostic)
-- ============================================================================

---Get source text from float attributes.
---Handles "source" attribute with preset defaults and "self" keyword.
---@param float table Float record with attributes
---@param preset table|nil Preset configuration
---@return string|nil source_text The source text, or nil if no source
function M.get_source_text(float, preset)
    local attrs = M.decode_attributes(float)

    -- Get source attribute
    local source = attrs.source

    -- Fall back to default if configured in preset.floats
    if not source or source == '' then
        local source_default = preset and preset.floats and preset.floats.source_default
        if source_default then
            source = source_default
        end
    end

    if not source or source == '' then
        return nil
    end

    -- Handle "self" keyword — preset.floats.source_self_text provides the replacement text
    if source:lower() == "self" then
        source = preset and preset.floats and preset.floats.source_self_text
        if not source then return nil end
    end

    return source
end

---Generate source attribution as Pandoc block.
---The source text is parsed as markdown to handle citations.
---Returns a Div with custom-style so it renders with proper styling.
---@param float table Float record with attributes
---@param preset table|nil Preset configuration
---@return table|nil Pandoc Div block with styled source paragraph, or nil
function M.get_source_block(float, preset)
    local source = M.get_source_text(float, preset)
    if not source then
        return nil
    end

    -- Get source style and template from preset.floats (required for source formatting)
    local source_style = preset and preset.floats and preset.floats.source_style
    local source_template = preset and preset.floats and preset.floats.source_template
    if not source_style or not source_template then return nil end
    local source_text = string.format(source_template, source)

    -- Parse source_text as markdown to handle citations
    -- This converts @citation patterns to proper Cite elements
    local parsed_doc = pandoc.read(source_text, 'markdown')
    local content_blocks = parsed_doc.blocks

    -- Create Pandoc Div with custom-style attribute
    -- Pandoc's writers will apply the custom-style as a paragraph style
    local source_div = pandoc.Div(
        content_blocks,
        pandoc.Attr("", {}, { ["custom-style"] = source_style })
    )

    return source_div
end

---Get caption position for a float type.
---@param type_ref string Float type (FIGURE, TABLE, MATH, etc.)
---@param preset table|nil Preset configuration
---@return string position 'before', 'after', 'inline', or 'none'
function M.get_caption_position(type_ref, preset)
    -- Check preset.floats.caption_positions
    if preset and preset.floats and preset.floats.caption_positions and preset.floats.caption_positions[type_ref] then
        return preset.floats.caption_positions[type_ref]
    end

    -- Default: caption before content, equations inline
    if type_ref == 'MATH' then
        return 'inline'
    end

    return 'before'
end

---Decode width/height from float attributes for image sizing.
---@param float table Float record with attributes
---@return table img_attrs Array of {key, value} pairs for Pandoc Attr
function M.decode_image_attrs(float)
    local img_attrs = {}
    local attrs = M.decode_attributes(float)

    if attrs.width then
        local w = tostring(attrs.width)
        if not w:match('[a-z%%]') then w = w .. 'px' end
        table.insert(img_attrs, {"width", w})
    end

    if attrs.height then
        local h = tostring(attrs.height)
        if not h:match('[a-z%%]') then h = h .. 'px' end
        table.insert(img_attrs, {"height", h})
    end

    return img_attrs
end

-- ============================================================================
-- Float Positioning (LaTeX-style specifiers)
-- ============================================================================

---Valid position specifiers for floats.
---@type table<string, boolean>
local VALID_POSITIONS = {
    h = true,  -- here: anchored at position with text wrapping
    t = true,  -- top: float to top of current page
    b = true,  -- bottom: float to bottom of current page
    p = true,  -- page: isolated float page (break before and after)
}

---Valid orientation values (only for position="p").
---@type table<string, boolean>
local VALID_ORIENTATIONS = {
    portrait = true,
    landscape = true,
}

---Get float position configuration from attributes.
---Returns nil for position if float should be inline (default behavior).
---@param float table Float record with attributes
---@param diagnostics table|nil Optional diagnostics for warnings
---@return table position_config {position=string|nil, orientation=string|nil}
function M.get_float_position(float, diagnostics)
    local attrs = M.decode_attributes(float)
    local result = {
        position = nil,
        orientation = nil,
    }

    -- Parse position attribute
    local pos = attrs.position
    if pos then
        pos = tostring(pos):lower()
        if VALID_POSITIONS[pos] then
            result.position = pos
        elseif diagnostics then
            diagnostics:warn(nil, nil, "FLOAT",
                string.format("Invalid position '%s' for float '%s'. Valid: h, t, b, p. Using inline.",
                    pos, float.anchor or float.label or "unknown"))
        end
    end

    -- Parse orientation attribute (only valid with position="p")
    local orient = attrs.orientation
    if orient then
        orient = tostring(orient):lower()
        if VALID_ORIENTATIONS[orient] then
            if result.position == "p" then
                result.orientation = orient
            elseif diagnostics then
                diagnostics:warn(nil, nil, "FLOAT",
                    string.format("Orientation '%s' ignored for float '%s': only valid with position=\"p\".",
                        orient, float.anchor or float.label or "unknown"))
            end
        elseif diagnostics then
            diagnostics:warn(nil, nil, "FLOAT",
                string.format("Invalid orientation '%s' for float '%s'. Valid: portrait, landscape.",
                    orient, float.anchor or float.label or "unknown"))
        end
    end

    return result
end

---Check if a float type supports positioning.
---MATH equations are inline-only per academic convention.
---@param type_ref string Float type (FIGURE, TABLE, MATH, etc.)
---@return boolean supports_position
function M.supports_positioning(type_ref)
    if not type_ref then return false end
    local upper = type_ref:upper()
    -- MATH equations are inline-only
    return upper ~= "MATH"
end

-- ============================================================================
-- Caption Configuration (from preset)
-- ============================================================================

---Get caption configuration for a float type from preset.
---Looks in enhanced_captions first, falls back to captions, then defaults.
---@param float_type string Float type (FIGURE, TABLE, LISTING, etc.) - REQUIRED
---@param preset table|nil Preset configuration
---@param float table|nil Float record with caption_format, counter_group from DB
---@return table caption_config {prefix, separator, style, seq_name, position}
function M.get_caption_config(float_type, preset, float)
    if not float_type or float_type == "" then
        error("Float type is required for get_caption_config but was nil or empty")
    end
    local type_upper = float_type:upper()
    local type_lower = type_upper:lower()

    -- Try enhanced_captions first, then captions
    local config = nil
    if preset then
        config = (preset.enhanced_captions and preset.enhanced_captions[type_lower])
              or (preset.captions and preset.captions[type_lower])
    end
    config = config or {}

    -- Use caption_format from database if available (model-defined)
    -- Falls back to preset config, then to type_ref
    local prefix = config.prefix
                or (float and float.caption_format)
                or type_upper

    -- Use counter_group for SEQ name (shared numbering)
    -- Falls back to preset config, then to type_ref
    local seq_name = config.sequence_name
                  or (float and float.counter_group)
                  or type_upper

    return {
        prefix = prefix,
        separator = config.separator or "–",
        style = config.style or "Caption",
        seq_name = seq_name,
        position = config.position or M.get_caption_position(type_upper, preset),
        source_style = config.source_style,
        source_prefix = config.source_prefix,
    }
end

---Generate caption as Pandoc Div block (format-agnostic).
---The Div includes custom attributes for backend to convert to format-specific output.
---@param float table Float record with type_ref, caption, identifier - type_ref is REQUIRED
---@param preset table|nil Preset configuration
---@return table|nil Pandoc Div with caption content, or nil if no caption
function M.get_caption_block(float, preset)
    if not float or not float.caption or float.caption == "" then
        return nil
    end

    if not float.type_ref or float.type_ref == "" then
        error("Float type_ref is required for get_caption_block but was nil or empty")
    end
    local type_ref = float.type_ref:upper()
    local config = M.get_caption_config(type_ref, preset, float)

    -- Build caption text: "Prefix {seq} separator caption"
    -- The {seq} placeholder will be replaced by backend with format-specific numbering
    local caption_text = string.format("%s {seq} %s %s",
        config.prefix, config.separator, float.caption)

    -- Create Pandoc Div with custom attributes for backend processing
    -- Backend will convert this to OOXML with SEQ field, or HTML with counter, etc.
    local caption_div = pandoc.Div(
        {pandoc.Para{pandoc.Str(caption_text)}},
        pandoc.Attr("", {"speccompiler-caption"}, {
            ["custom-style"] = config.style,
            ["seq-name"] = config.seq_name,
            ["float-id"] = float.anchor or float.label or "",
            ["float-type"] = type_ref,
        })
    )

    return caption_div
end

---Wrap float content with caption and source decoration.
---Returns format-agnostic Pandoc blocks that backend converts to output format.
---@param float table Float record (type_ref, caption, attributes, identifier) - type_ref is REQUIRED
---@param content table Array of Pandoc content blocks
---@param preset table|nil Preset configuration
---@return table Decorated blocks array
function M.render_with_decoration(float, content, preset)
    if not float then
        return content or {}
    end

    if not float.type_ref or float.type_ref == "" then
        error("Float type_ref is required for render_with_decoration but was nil or empty")
    end
    local type_ref = float.type_ref:upper()
    local config = M.get_caption_config(type_ref, preset, float)
    local position = config.position

    -- Inline or none: no decoration (e.g., equations handle own numbering)
    if position == 'inline' or position == 'none' then
        return content or {}
    end

    local blocks = {}

    -- Get caption block
    local caption_block = M.get_caption_block(float, preset)

    -- Get source block (already exists in float_base)
    local source_block = M.get_source_block(float, preset)

    if position == 'before' then
        -- Caption above content, source below
        if caption_block then
            table.insert(blocks, caption_block)
        end

        for _, block in ipairs(content or {}) do
            table.insert(blocks, block)
        end

        if source_block then
            table.insert(blocks, source_block)
        end
    else
        -- 'after': Content first, then caption, then source
        for _, block in ipairs(content or {}) do
            table.insert(blocks, block)
        end

        if caption_block then
            table.insert(blocks, caption_block)
        end

        if source_block then
            table.insert(blocks, source_block)
        end
    end

    return blocks
end

return M
