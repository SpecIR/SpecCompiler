---Math type module for SpecCompiler.
---Converts AsciiMath → MathML → native pandoc.Math at render time via
---math_render_utils.mathml_to_pandoc_math. No external process; Pandoc's
---native writers handle format conversion (OMML for DOCX, MathML for HTML).
---@module math
local float_base = require("pipeline.shared.float_base")
local math_utils = require("pipeline.shared.math_render_utils")

local M = {}

M.float = {
    id = "MATH",
    long_name = "Math",
    description = "A mathematical expression (AsciiMath)",
    caption_format = "Equation",
    counter_group = "EQUATION",
    aliases = { "math", "asciimath", "equation", "eq" },
    style_id = "MATH",
    -- NOTE: needs_external_render removed — math converts inline at EMIT.
}

M.handler = {
    name = "math_handler",
    prerequisites = {},

    ---TRANSFORM: Stamp a sentinel resolved_ast so float_resolver will dispatch
    ---to on_render_CodeBlock at EMIT. Actual conversion happens at render time.
    ---@param data DataManager
    ---@param contexts table
    ---@param diagnostics table
    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local floats = float_base.query_floats_by_type(data, ctx, "MATH")
            for _, float in ipairs(floats or {}) do
                -- Sentinel: keeps MATH on the generic resolved-float dispatch path instead
                -- of the MATH-specific nil-resolved_ast branch in float_resolver.lua
                -- (removed in a later task). The value itself is ignored by
                -- on_render_CodeBlock, which re-derives everything from float.raw_content.
                float_base.update_resolved_ast(data, float.id, "render-at-emit")
            end
        end
    end,

    ---EMIT: Convert AsciiMath code-block to a numbered-equation Div wrapping a
    ---native pandoc.Math element.
    ---@param block table Pandoc CodeBlock element (unused; kept for handler contract)
    ---@param ctx table Context (data, spec_id, log, preset)
    ---@param float table Float record from database (raw_content has the AsciiMath)
    ---@return table|nil Pandoc element or nil
    on_render_CodeBlock = function(block, ctx, float, _resolved)
        local mathml, err = math_utils.asciimath_to_mathml(float.raw_content or "", "block")
        if not mathml then
            ctx.log.warn("AsciiMath conversion failed for %s: %s", tostring(float.id), err or "")
            return nil
        end

        local math_elt = math_utils.mathml_to_pandoc_math(mathml, "block")
        if not math_elt then
            ctx.log.warn("MathML→pandoc.Math failed for %s", tostring(float.id))
            return nil
        end

        local math_config = float_base.get_caption_config("MATH", ctx.preset)
        local seq_name = math_config.seq_name or "Equation"

        return pandoc.Div(
            { pandoc.Para({ math_elt }) },
            pandoc.Attr("", { "speccompiler-numbered-equation" }, {
                ["seq-name"]   = seq_name,
                ["number"]     = tostring(float.number or ""),
                ["identifier"] = float.anchor or float.label or "",
            })
        )
    end
}

return M
