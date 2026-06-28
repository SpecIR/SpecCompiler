---Float Emission for SpecCompiler.
---Handles Pandoc document transformation for floats during EMIT phase.
---Replaces code blocks with rendered content and adds decorations (captions, bookmarks).
---
---Floats are CodeBlock elements only. Views (Code elements) are handled by emit_view.lua.
---
---@module emit_float
local M = {}

local float_base = require("pipeline.shared.float_base")
local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")
local float_anchor = require("pipeline.shared.float_anchor")

-- Internal float rendering is dispatched through the host's hook index
-- (_caps.float.<TYPE>.render), which already overlays default+template.

-- Bookmark ids come from float_anchor.bookmark_id (single source of truth).

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

    -- Add bookmark start marker (format-agnostic). The bookmark NAME is the
    -- float's canonical reference anchor -- the single string every PAGEREF /
    -- cross-reference to this float must resolve to (see float_anchor / VC-ABNT-002).
    local ref_anchor = float_anchor.ref_anchor(float)
    if ref_anchor then
        local bm_id = float_anchor.bookmark_id(ref_anchor)
        table.insert(blocks, pandoc.RawBlock('speccompiler',
            string.format('bookmark-start:%d:%s', bm_id, ref_anchor)))
    end

    -- Create format-agnostic caption Div (filters will convert to OOXML/HTML)
    local caption_div = nil
    if float.caption and float.caption ~= '' then
        caption_div = pandoc.Div(
            {pandoc.Para{pandoc.Str(float.caption)}},
            pandoc.Attr("", {"speccompiler-caption"}, {
                ["seq-name"] = config.seq_name,
                ["float-id"] = ref_anchor or "",
                ["float-type"] = type_ref,
                ["float-number"] = tostring(float.number or ""),
                ["prefix"] = config.prefix,
                ["separator"] = config.separator,
                ["style"] = config.style or "Caption",
            })
        )
    end

    -- Get source line (format-agnostic semantic Div with custom-style)
    local source_block = float_base.get_source_block(float, preset, config)

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
    if ref_anchor then
        local bm_id = float_anchor.bookmark_id(ref_anchor)
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
---@return pandoc.Pandoc Transformed document
function M.transform_floats_in_doc(doc, float_results, data, spec_id, log, preset, pctx, diagnostics)

    -- The host owns internal float render dispatch; its _caps.float index is
    -- already overlaid (default then template), so no per-model lookup here.
    local host = registry.current()

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
                -- nil here covers BOTH "type not registered" and "registered but
                -- no render hook" (e.g. FIGURE renders via the image fallback);
                -- both correctly fall through below.
                local render = host and host:get_hook_inherited("float", float_type_ref:upper(), "render")
                if render then
                    local fctx = hook_ctx.build(pctx, data, diagnostics, {
                        element = block,
                        float = result.float,
                        resolved = result.resolved,
                        preset = preset,
                    }, "render", spec_id)
                    local handler_result = render(fctx)
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
