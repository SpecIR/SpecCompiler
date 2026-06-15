---Specification Base utilities for SpecCompiler.
---Shared infrastructure for specification type handlers.
---
---Provides:
---  - Default header rendering (H1 document title)
---  - Configurable title formatting (unnumbered, with/without PID)
---  - title_render: the host-owned standard title renderer (registered on the
---    SPEC_TITLE base type; concrete spec types inherit it and stay pure schema)
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

---The host-owned standard specification-title renderer (a styled Title Div).
---Registered as the render hook of the SPEC_TITLE base type; concrete spec types
---inherit it through the host's extends-chain dispatch and declare their options
---(show_pid, style) as plain SCHEMA fields, read here from the rendering type's
---schema (ctx.subject.type_schema). A spec wanting a custom render declares its
---own hooks.render (e.g. SBES_PAPER); the default SPEC type does NOT extend
---SPEC_TITLE, so untyped H1 documents render no title.
---@param ctx table canonical ctx (subject.specification/type_schema, pandoc)
---@return table|nil header Pandoc Div, or nil
function M.title_render(ctx)
    return M.header(
        { specification = ctx.subject.specification, spec_id = ctx.spec_id },
        ctx.pandoc,
        ctx.subject.type_schema or {})
end

return M
