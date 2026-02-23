---Float Emission for SpecCompiler.
---Handles Pandoc document transformation for floats during EMIT phase.
---Replaces code blocks with rendered content and adds decorations (captions, bookmarks).
---
---Floats are CodeBlock elements only. Views (Code elements) are handled by emit_view.lua.
---
---@module emit_float
local M = {}

local float_base = require("pipeline.shared.float_base")

-- Note: pandoc.json.decode only works for Pandoc AST JSON, not arbitrary JSON objects.
-- We use dkjson for decoding simple JSON like {"content":"...", "language":"c"}
local dkjson = require("dkjson")

-- Cache for loaded float type handlers
local float_handler_cache = {}

---Load float type handler module.
---@param type_ref string Float type (e.g., "TABLE", "MATH", "LISTING")
---@param model_name string Model name (e.g., "default")
---@return table|nil handler with on_render_CodeBlock or nil
local function get_float_handler(type_ref, model_name)
    if not type_ref then return nil end
    local cache_key = type_ref:upper() .. ":" .. (model_name or "default")

    if float_handler_cache[cache_key] ~= nil then
        return float_handler_cache[cache_key] or nil
    end

    local paths = {
        "models." .. (model_name or "default") .. ".types.floats." .. type_ref:lower(),
        "models.default.types.floats." .. type_ref:lower()
    }

    for _, module_path in ipairs(paths) do
        local ok, module = pcall(require, module_path)
        if ok and module and module.handler and module.handler.on_render_CodeBlock then
            float_handler_cache[cache_key] = module.handler
            return module.handler
        end
    end

    float_handler_cache[cache_key] = false
    return nil
end

---Generate bookmark ID from identifier string.
---@param identifier string The identifier to hash
---@return number Bookmark ID
local function generate_bookmark_id(identifier)
    local bm_id = 0
    for i = 1, #identifier do
        bm_id = (bm_id * 31 + identifier:byte(i)) % 100000
    end
    return bm_id + 1  -- Ensure non-zero
end

---Wrap float content with caption and source lines.
---Uses format-agnostic markers that filters convert to format-specific output.
---@param float table Float record (type_ref, caption, attributes)
---@param content table Array of Pandoc content blocks
---@param preset table|nil Configuration for styles
---@return table Decorated blocks array
local function render_with_decoration(float, content, preset)
    if not float then
        return content
    end

    if not float.type_ref or float.type_ref == "" then
        error("Float type_ref is required for render_with_decoration but was nil or empty")
    end
    local type_ref = float.type_ref:upper()
    local position = float_base.get_caption_position(type_ref, preset)

    -- Inline or none: no decoration (e.g., equations handle own numbering)
    if position == 'inline' or position == 'none' then
        return content
    end

    local blocks = {}

    -- Get caption config for format-agnostic Div
    local config = float_base.get_caption_config(type_ref, preset, float)

    -- Add bookmark start marker (format-agnostic)
    if float.anchor or float.label then
        local bm_id = generate_bookmark_id(float.anchor or float.label)
        table.insert(blocks, pandoc.RawBlock('speccompiler',
            string.format('bookmark-start:%d:%s', bm_id, float.anchor or float.label)))
    end

    -- Create format-agnostic caption Div (filters will convert to OOXML/HTML)
    local caption_div = nil
    if float.caption and float.caption ~= '' then
        caption_div = pandoc.Div(
            {pandoc.Para{pandoc.Str(float.caption)}},
            pandoc.Attr("", {"speccompiler-caption"}, {
                ["seq-name"] = config.seq_name,
                ["float-id"] = float.anchor or float.label or "",
                ["float-type"] = type_ref,
                ["float-number"] = tostring(float.number or ""),
                ["prefix"] = config.prefix,
                ["separator"] = config.separator,
                ["style"] = config.style or "Caption",
            })
        )
    end

    -- Get source line (already format-agnostic Pandoc Div with custom-style)
    local source_block = float_base.get_source_block(float, preset)

    if position == 'before' then
        -- Caption above content, source below
        if caption_div then
            table.insert(blocks, caption_div)
        end

        for _, block in ipairs(content) do
            table.insert(blocks, block)
        end

        if source_block then
            table.insert(blocks, source_block)
        end
    else
        -- 'after': Content first, then caption, then source
        for _, block in ipairs(content) do
            table.insert(blocks, block)
        end

        if caption_div then
            table.insert(blocks, caption_div)
        end

        if source_block then
            table.insert(blocks, source_block)
        end
    end

    -- Add bookmark end marker (format-agnostic)
    if float.anchor or float.label then
        local bm_id = generate_bookmark_id(float.anchor or float.label)
        table.insert(blocks, pandoc.RawBlock('speccompiler',
            string.format('bookmark-end:%d', bm_id)))
    end

    return blocks
end

---Strip Pandoc attribute syntax from a string.
---Removes everything from first { to end (e.g., "gauss{caption=...}" -> "gauss")
---@param str string|nil Input string
---@return string|nil Cleaned string
local function strip_pandoc_attrs(str)
    if not str then return str end
    return str:match('^([^{]+)') or str
end

---Transform document by replacing float references with rendered content.
---This walks the Pandoc AST and replaces code blocks with rendered images/content.
---Floats only - views (Code elements) are handled by emit_view.lua.
---@param doc pandoc.Pandoc The document to transform
---@param float_results table Map of float ID to render result
---@param data DataManager Database for lookups
---@param spec_id string Specification ID
---@param log table Logger
---@param preset table|nil Preset configuration for caption prefixes/styles
---@param template string|nil Template name (e.g., "emb", "abnt")
---@return pandoc.Pandoc Transformed document
function M.transform_floats_in_doc(doc, float_results, data, spec_id, log, preset, template)
    local model_name = template or "default"

    -- Context passed to float handler modules
    local handler_ctx = {
        data = data,
        spec_id = spec_id,
        log = log,
        dkjson = dkjson,
        pandoc = pandoc,
        preset = preset,
        template = model_name,
    }

    return doc:walk({
        -- Handle CodeBlock float references only
        -- View Code elements are handled by emit_view.lua
        CodeBlock = function(block)
            local classes = block.classes or {}
            local first_class = classes[1] or ""

            -- Strip Pandoc attribute syntax if present (e.g., "math:gauss{caption=...}" -> "math:gauss")
            first_class = strip_pandoc_attrs(first_class)

            -- Float classes are in format "type:label" (e.g., "math:pitagoras", "csv:data")
            -- or "type.lang:label" (e.g., "listing.lua:my-module", "src.c:hello")
            local float_type, float_label = first_class:match("^([^:]+):(.+)$")
            if not float_type then
                -- No colon separator means this is a plain language code block (e.g., "lua", "python")
                -- not a float reference - skip without logging
                return nil
            end

            -- Strip nested attrs from label if present
            float_label = strip_pandoc_attrs(float_label)

            -- Use first_class directly as lookup key (matches syntax_key stored in database)
            local lookup_key = first_class

            -- Look up rendered result from float_resolver pre-loaded map
            local result = float_results[lookup_key]

            if not result then
                log.debug("No render result for float: %s (key: %s)", first_class, lookup_key)
                return nil  -- Keep original code block
            end

            log.debug("Found float result for key: %s (type_ref: %s)", lookup_key, result.float and result.float.type_ref or "unknown")

            -- Dispatch to float type handler based on float.type_ref
            local float_type_ref = result.float and result.float.type_ref
            if float_type_ref then
                local handler = get_float_handler(float_type_ref, model_name)
                if handler and handler.on_render_CodeBlock then
                    local handler_result = handler.on_render_CodeBlock(block, handler_ctx, result.float, result.resolved)
                    if handler_result then
                        -- Wrap with decoration (caption, bookmarks)
                        local content = type(handler_result) == "table" and handler_result.t and {handler_result} or
                                       (type(handler_result) == "table" and handler_result or {handler_result})
                        return render_with_decoration(result.float, content, preset)
                    end
                end
            end

            -- Fallback for image type (external renderers like PlantUML set type="image")
            if result.type == "image" and result.paths and #result.paths > 0 then
                local img_path = result.paths[1]

                -- Get width/height from float attributes
                local img_attrs = {}
                if result.float then
                    img_attrs = float_base.decode_image_attrs(result.float)
                end

                -- Create image element with attributes
                local img = pandoc.Image(
                    {},  -- alt text handled by caption
                    img_path,
                    "",
                    pandoc.Attr("", {}, img_attrs)
                )
                local content = {pandoc.Para({img})}

                -- Wrap with caption and source decoration
                if result.float then
                    return render_with_decoration(result.float, content, preset)
                else
                    return content
                end
            end

            log.debug("No handler or fallback for float: %s (type_ref: %s)", first_class, float_type_ref or "nil")
            return nil  -- Keep original if no transformation
        end
    })
end

return M
