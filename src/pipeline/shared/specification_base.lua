---Specification Base utilities for SpecCompiler.
---Shared infrastructure for specification type handlers.
---
---Provides:
---  - Default header rendering (H1 document title)
---  - Configurable title formatting (unnumbered, with/without PID)
---  - Extensible rendering via create_handler()
---
---@module specification_base
local M = {}

-- ============================================================================
-- Default Rendering Functions
-- ============================================================================

---Default header rendering for specifications.
---Renders the document title as a styled Div (not a Header).
---Using a Div instead of Header prevents it from affecting section numbering.
---This allows Introduction to be numbered "1" instead of "0.1".
---@param ctx table Render context (specification record, config)
---@param pandoc table Pandoc module
---@param options table|nil Rendering options {show_pid, style}
---@return table Pandoc Div element containing Para with title
function M.header(ctx, pandoc, options)
    options = options or {}
    local spec = ctx.specification
    local long_name = spec.long_name or ""
    local pid = spec.pid or ""

    -- Build title inlines
    local title_inlines = {}
    if options.show_pid and pid ~= "" then
        table.insert(title_inlines, pandoc.Str(pid))
        table.insert(title_inlines, pandoc.Str(": "))
    end
    table.insert(title_inlines, pandoc.Str(long_name))

    -- Create a Para containing the title text
    local title_para = pandoc.Para(title_inlines)

    -- Wrap in a Div with title styling (not a Header, so no numbering impact)
    -- The PID serves as anchor for cross-references
    local anchor_id = pid ~= "" and pid or spec.identifier
    local title_div = pandoc.Div({title_para}, pandoc.Attr(anchor_id, {"spec-title"}, {
        ["custom-style"] = options.style or "Title"
    }))

    return title_div
end

-- ============================================================================
-- Handler Factory
-- ============================================================================

---Create a handler for a specification type.
---Supports customization via options table.
---
---Options:
---  - unnumbered: boolean (default true) - exclude from section numbering
---  - show_pid: boolean (default false) - show "PID: Title" vs just "Title"
---  - style: string (default "Title") - custom-style for the header
---  - header: custom header function(ctx, pandoc)
---
---@param name string Handler name (e.g., "srs_handler")
---@param options table|nil Customization options
---@return table Handler module with on_render_Specification
function M.create_handler(name, options)
    options = options or {}

    local handler = {
        name = name,
        prerequisites = options.prerequisites or {},
    }

    -- Header function: use custom or default
    if options.header then
        handler.header = options.header
    else
        handler.header = function(ctx, pandoc)
            return M.header(ctx, pandoc, options)
        end
    end

    ---Render the specification header.
    ---Called by specification_render_handler during TRANSFORM phase.
    ---@param ctx table Render context {specification, spec_id}
    ---@param pandoc table Pandoc module
    ---@param data DataManager Database manager
    ---@return table|nil header Pandoc Header block, or nil to skip
    function handler.on_render_Specification(ctx, pandoc, data)
        return handler.header(ctx, pandoc)
    end

    return handler
end

return M
