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
    return logger.create_diagnostic_adapter(diagnostics, "FLOAT")
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

return M
