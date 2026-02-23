---View Emission for SpecCompiler.
---Handles Pandoc document transformation for views during EMIT phase.
---
---Views are Code (inline) elements only. Floats (CodeBlock elements) are handled by emit_float.lua.
---
---Handles two cases:
---  1. Inline Code within mixed content → on_render_Code → returns inline elements
---  2. Standalone Code in Para → on_render_CodeBlock → returns block elements
---
---@module emit_view
local M = {}

local inline_handlers = require("pipeline.emit.inline_handlers")

-- Shared state for inline handlers (e.g., tracking first-use abbreviations)
-- This persists across the document walk
local inline_state = {}

---Transform views in document.
---Handles inline Code elements and standalone Code-in-Para for block output.
---@param doc pandoc.Pandoc The document to transform
---@param data DataManager Database for view lookups
---@param spec_id string Specification ID
---@param log table Logger
---@param template string|nil Template/model name
---@return pandoc.Pandoc Transformed document
function M.transform_views_in_doc(doc, data, spec_id, log, template)
    local model_name = template or "default"
    local handlers = inline_handlers.get_inline_handlers(data, model_name)

    -- Reset state for each document
    inline_state = {}

    local handler_ctx = {
        data = data,
        spec_id = spec_id,
        log = log,
        state = inline_state,
        pandoc = pandoc,
        template = model_name,
    }

    -- Two-pass walk: block-level promotion FIRST, then inline views.
    -- Pandoc walks inner elements (Code) before outer elements (Para),
    -- so a single walk would have the Code handler replace `toc:` with
    -- a Str placeholder before the Para handler can see it.

    -- Pass 1: Promote standalone Code-in-Para to block content (BulletList)
    doc = doc:walk({
        Para = function(para)
            -- Check if Para has exactly one element that is a Code
            if #para.content ~= 1 then return nil end
            local elem = para.content[1]
            if elem.t ~= "Code" then return nil end

            local text = elem.text or ""

            -- Try to match against registered inline view handlers
            local text_lower = text:lower()
            for _, handler in ipairs(handlers) do
                local prefix_colon = handler.prefix .. ":"
                if text_lower:sub(1, #prefix_colon) == prefix_colon then
                    -- Use on_render_CodeBlock for block output (not on_render_Code)
                    if handler.view_module.handler and
                       handler.view_module.handler.on_render_CodeBlock then
                        -- Create synthetic CodeBlock for the handler
                        local synthetic = pandoc.CodeBlock(text,
                            pandoc.Attr("", {handler.prefix}))
                        local result = handler.view_module.handler.on_render_CodeBlock(
                            synthetic, handler_ctx)
                        if result then
                            log.debug("View Para handler: %s -> block", handler.identifier)
                            return result
                        end
                    end
                end
            end

            return nil  -- Keep original Para
        end
    })

    -- Pass 2: Handle remaining inline Code views (e.g., `abbrev:term`, `math:expr`)
    return doc:walk({
        Code = function(code)
            local text = code.text or ""

            -- Try to match against registered inline view handlers
            local text_lower = text:lower()
            for _, handler in ipairs(handlers) do
                local prefix_colon = handler.prefix .. ":"
                if text_lower:sub(1, #prefix_colon) == prefix_colon then
                    -- Call the view type's on_render_Code handler
                    if handler.view_module.handler and handler.view_module.handler.on_render_Code then
                        local result = handler.view_module.handler.on_render_Code(code, handler_ctx)
                        if result then
                            log.debug("View inline handler %s processed: %s",
                                handler.identifier, text:sub(1, 20))
                            return result
                        end
                    end
                end
            end

            return nil  -- Keep original Code
        end
    })
end

return M
