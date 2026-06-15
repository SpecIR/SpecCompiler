---View Emission for SpecCompiler.
---Handles Pandoc document transformation for views during EMIT phase.
---
---Views are Code (inline) elements only. Floats (CodeBlock elements) are handled by emit_float.lua.
---
---Handles two cases:
---  1. Inline Code within mixed content → view "render" hook → returns inline elements
---  2. Standalone Code in Para → view "render_block" hook → returns block elements
---
---@module emit_view
local M = {}

local registry = require("contract.registry")
local hook_ctx = require("pipeline.shared.hook_ctx")

-- Shared state for inline handlers (e.g., tracking first-use abbreviations)
-- This persists across the document walk
local inline_state = {}

---Transform views in document.
---Handles inline Code elements and standalone Code-in-Para for block output.
---@param doc pandoc.Pandoc The document to transform
---@param data DataManager Database for view lookups
---@param spec_id string Specification ID
---@param log table Logger
---@return pandoc.Pandoc Transformed document
function M.transform_views_in_doc(doc, data, spec_id, log, pctx, diagnostics)

    -- Inline view dispatch reads the host: the prefix -> view-id map and the
    -- per-view render hooks (render for inline, render_block for block output).
    local host = registry.current()
    local inline_views = host and host:get_inline_views() or {}

    -- Reset state for each document
    inline_state = {}

    -- Build the canonical frozen ctx (HLR-EXT-009) for a view hook: the matched
    -- Code/CodeBlock element is the subject; inline_state persists across the walk.
    local function view_ctx(element, capability, view_id)
        return hook_ctx.build(pctx, data, diagnostics,
            { element = element, state = inline_state, view_id = view_id }, capability, spec_id)
    end

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
            for _, iv in ipairs(inline_views) do
                local prefix_colon = iv.prefix .. ":"
                if text_lower:sub(1, #prefix_colon) == prefix_colon then
                    -- Block-promoted output uses the view's render_block hook,
                    -- not the inline render hook.
                    local render_block = host:get_hook_inherited("view", iv.id, "render_block")
                    if render_block then
                        -- Create synthetic CodeBlock for the handler
                        local synthetic = pandoc.CodeBlock(text,
                            pandoc.Attr("", {iv.prefix}))
                        local result = render_block(view_ctx(synthetic, "render_block", iv.id))
                        if result then
                            log.debug("View Para handler: %s -> block", iv.id)
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
            for _, iv in ipairs(inline_views) do
                local prefix_colon = iv.prefix .. ":"
                if text_lower:sub(1, #prefix_colon) == prefix_colon then
                    -- Inline output uses the view's render hook.
                    local render = host:get_hook_inherited("view", iv.id, "render")
                    if render then
                        local result = render(view_ctx(code, "render", iv.id))
                        if result then
                            log.debug("View inline handler %s processed: %s",
                                iv.id, text:sub(1, 20))
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
