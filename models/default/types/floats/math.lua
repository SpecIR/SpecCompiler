---Math type module for SpecCompiler.
---Converts AsciiMath → MathML → native pandoc.Math at TRANSFORM time, storing
---the TeX text of the Math element in resolved_ast. EMIT reconstructs
---pandoc.Math("DisplayMath", tex) and wraps it in the numbered-equation Div.
---Pandoc's native writers handle format conversion (OMML for DOCX, MathML for HTML).
---@module math
local float_base = require("pipeline.shared.float_base")
local math_utils = require("pipeline.shared.math_render_utils")

---TRANSFORM: convert AsciiMath -> MathML -> native pandoc.Math and return the
---resulting TeX text (stored as resolved_ast; EMIT reconstructs the Math from it).
---@param raw_content string
---@param _float table
---@param log table|nil
---@return string|nil tex
local function transform(dctx)
    local raw_content = dctx.subject.raw_content
    local log = dctx.log
    local mathml, err = math_utils.asciimath_to_mathml(raw_content or "", "block")
    if not mathml then
        if log then log.warn("AsciiMath conversion failed: %s", err or "unknown") end
        return nil
    end
    local math_elt = math_utils.mathml_to_pandoc_math(mathml, "block")
    if math_elt and math_elt.text and math_elt.text ~= "" then
        return math_elt.text
    end
    if log then log.warn("MathML->pandoc.Math produced empty TeX") end
    return nil
end

return {
    kind = "float",

    schema = {
        id = "MATH",
        long_name = "Math",
        description = "A mathematical expression (AsciiMath)",
        caption_format = "Equation",
        counter_group = "EQUATION",
        aliases = { "math", "asciimath", "equation", "eq" },
        -- NOTE: needs_external_render removed — math converts inline at TRANSFORM.
    },

    hooks = {
        ---EMIT: Reconstruct a native pandoc.Math from the stored TeX and wrap it
        ---in the speccompiler-numbered-equation Div so filters handle numbering.
        ---@param ctx table Canonical ctx (subject.resolved/float/preset, pandoc)
        ---@return table|nil
        render = function(ctx)
            local resolved = ctx.subject.resolved
            if not resolved or resolved == "" then return nil end

            local pandoc = ctx.pandoc
            local float = ctx.subject.float
            local math_elt = pandoc.Math("DisplayMath", resolved)

            local math_config = float_base.get_caption_config("MATH", ctx.subject.preset)
            local seq_name = math_config.seq_name or "Equation"

            return pandoc.Div(
                { pandoc.Para({ math_elt }) },
                pandoc.Attr("", { "speccompiler-numbered-equation" }, {
                    ["seq-name"]   = seq_name,
                    ["number"]     = tostring(float.number or ""),
                    ["identifier"] = float.anchor or float.label or "",
                })
            )
        end,

        -- TRANSFORM: AsciiMath -> TeX text (decoded by render above).
        transform = transform,
    },
}
