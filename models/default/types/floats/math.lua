---Math type module for SpecCompiler.
---Converts AsciiMath → MathML → native pandoc.Math at TRANSFORM time, storing
---the TeX text of the Math element in resolved_ast. EMIT reconstructs
---pandoc.Math("DisplayMath", tex) and wraps it in the numbered-equation Div.
---Pandoc's native writers handle format conversion (OMML for DOCX, MathML for HTML).
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
    -- NOTE: needs_external_render removed — math converts inline at TRANSFORM.
}

M.handler = {
    name = "math_handler",
    prerequisites = {},

    ---TRANSFORM: Convert AsciiMath → MathML → native pandoc.Math and store the
    ---resulting TeX text in resolved_ast. The EMIT handler reconstructs
    ---pandoc.Math("DisplayMath", tex) from the stored text.
    ---@param data DataManager
    ---@param contexts table
    ---@param diagnostics table
    on_transform = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts or {}) do
            local log = float_base.create_log(diagnostics)
            local floats = float_base.query_floats_by_type(data, ctx, "MATH")
            for _, float in ipairs(floats or {}) do
                if float.resolved_ast == nil or float.resolved_ast == "" then
                    local mathml, err = math_utils.asciimath_to_mathml(float.raw_content or "", "block")
                    if mathml then
                        local math_elt = math_utils.mathml_to_pandoc_math(mathml, "block")
                        if math_elt and math_elt.text and math_elt.text ~= "" then
                            float_base.update_resolved_ast(data, float.id, math_elt.text)
                        else
                            log.warn("MathML→pandoc.Math failed for float %s", tostring(float.id))
                        end
                    else
                        log.warn("AsciiMath conversion failed for float %s: %s",
                            tostring(float.id), err or "unknown")
                    end
                end
            end
        end
    end,

    ---EMIT: Reconstruct a native pandoc.Math from the stored TeX and wrap it
    ---in the speccompiler-numbered-equation Div so filters handle numbering.
    ---@param _block pandoc.CodeBlock
    ---@param ctx table Context (data, spec_id, log, preset)
    ---@param float table Float record from database
    ---@param resolved string|nil TeX text stored by on_transform
    ---@return table|nil
    on_render_CodeBlock = function(_block, ctx, float, resolved)
        if not resolved or resolved == "" then return nil end

        local math_elt = pandoc.Math("DisplayMath", resolved)

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
