---Inline Math view type module.
---Handles inline AsciiMath expressions like `math: x^2 + y^2`.
---Converts AsciiMath → MathML → native pandoc.Math at EMIT time.
---
---For block equations with numbering, see floats/math.lua
---
---@module views.math
local M = {}

local math_utils = require("pipeline.shared.math_render_utils")
local Queries = require("db.queries")

M.view = {
    id = "MATH_INLINE",
    long_name = "Inline Math",
    description = "Inline mathematical expressions (AsciiMath)",
    aliases = { "eq", "formula", "$" },
    inline_prefix = "math",  -- Enables math:/eq:/formula: syntax dispatch
    -- NOTE: needs_external_render removed — inline math renders natively at EMIT
}

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_math_code = prefix_matcher.from_decl(M.view, { require_content = true })

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "math_inline_handler",
    prerequisites = {"spec_views"},  -- Run AFTER spec_views clears and processes

    ---INITIALIZE: Record inline math views in spec_views for parity with other
    ---view types (and potential future xref discovery). The stored raw_ast is
    ---not consumed by on_render_Code — the Code element's text has the expression.
    ---@param data DataManager
    ---@param contexts Context[]
    ---@param diagnostics Diagnostics
    on_initialize = function(data, contexts, diagnostics)
        for _, ctx in ipairs(contexts) do
            local doc = ctx.doc
            if not doc or not doc.blocks then goto continue end

            local spec_id = ctx.spec_id or "default"
            local file_seq = 0

            local visitor = {
                Code = function(c)
                    local expr = match_math_code(c.text or "")
                    if expr then
                        file_seq = file_seq + 1
                        local content_key = spec_id .. ":" .. file_seq .. ":" .. expr
                        local identifier = pandoc.sha1(content_key)

                        data:execute(Queries.content.insert_view, {
                            identifier = identifier,
                            specification_ref = spec_id,
                            view_type_ref = "MATH_INLINE",
                            from_file = ctx.source_path or "unknown",
                            file_seq = file_seq,
                            raw_ast = expr  -- Store the expression
                        })
                    end
                end
            }

            for _, block in ipairs(doc.blocks) do
                pandoc.walk_block(block, visitor)
            end

            ::continue::
        end
    end,

    ---EMIT: Render inline Code elements with math syntax as native pandoc.Math.
    ---Pandoc's docx writer natively emits <m:oMath>; HTML writer emits MathML
    ---(with --mathml) or MathJax/KaTeX — no custom filter code required.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Replacement inlines
    on_render_Code = function(code, ctx)
        local expr = match_math_code(code.text or "")
        if not expr then return nil end

        local mathml, err = math_utils.asciimath_to_mathml(expr, "inline")
        if not mathml then
            ctx.log.warn("Inline AsciiMath conversion failed: %s", err or "")
            return nil
        end

        local math_elt = math_utils.mathml_to_pandoc_math(mathml, "inline")
        if not math_elt then
            ctx.log.warn("MathML→pandoc.Math failed for inline expression")
            return nil
        end

        return { math_elt }
    end
}

return M
