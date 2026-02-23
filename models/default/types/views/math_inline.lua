---Inline Math view type module.
---Handles inline AsciiMath expressions like `math: x^2 + y^2`.
---Uses external_render_handler for parallel batch MathML→OMML conversion.
---
---For block equations with numbering, see floats/math.lua
---
---@module views.math
local M = {}

local task_runner = require("infra.process.task_runner")
local external_render = require("pipeline.transform.external_render_handler")
local math_utils = require("pipeline.shared.math_render_utils")
local Queries = require("db.queries")

M.view = {
    id = "MATH_INLINE",
    long_name = "Inline Math",
    description = "Inline mathematical expressions (AsciiMath)",
    aliases = { "eq", "formula", "$" },
    inline_prefix = "math",  -- Enables math:/eq:/formula: syntax dispatch
    needs_external_render = true,  -- Enable batch processing via external_render_handler
}

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_math_code = prefix_matcher.from_decl(M.view, { require_content = true })

-- ============================================================================
-- External Render Registration (parallel batch processing)
-- ============================================================================

external_render.register_renderer("MATH_INLINE", {
    ---Prepare a spawn task for MathML→OMML conversion.
    ---@param view table View record from database
    ---@param build_dir string Build directory path
    ---@param log table Logger
    ---@param data DataManager Database instance
    ---@param model_name string Model name
    ---@return table|nil task Task descriptor or nil to skip
    prepare_task = function(view, build_dir, log, data, model_name)
        -- view.raw_ast contains the expression (e.g., "x^2 + y^2")
        local mathml, err = math_utils.asciimath_to_mathml(view.raw_ast, "inline")
        if not mathml then
            log.warn("Failed to convert inline AsciiMath for %s: %s", tostring(view.id), err or "unknown")
            return nil
        end

        local hash = math_utils.hash_content(mathml)

        -- Use temp file for input (no disk cache - database has the result)
        local input_file = os.tmpname() .. "_" .. hash .. ".mml"

        local render_script, is_compiled = math_utils.find_render_script(os.getenv("SPECCOMPILER_HOME"))
        if not render_script then
            log.warn("mml2omml script not found")
            return nil
        end

        local runtime_ok, runtime_err = math_utils.ensure_runtime(is_compiled)
        if not runtime_ok then
            log.warn(runtime_err or "Math renderer runtime unavailable")
            return nil
        end

        -- Write MathML to input file
        local write_ok, write_err = task_runner.write_file(input_file, mathml)
        if not write_ok then
            log.warn("Failed to write MathML: %s", write_err or "unknown")
            return nil
        end

        log.debug("Preparing inline math conversion: %s", hash:sub(1, 12))

        local cmd, args = math_utils.build_render_command(render_script, is_compiled, input_file)

        return {
            cmd = cmd,
            args = args,
            opts = { timeout = 10000 },
            context = {
                hash = hash,
                view = view,
                input_file = input_file,
                mathml = mathml  -- Pass MathML to handle_result for format-agnostic storage
            }
        }
    end,

    ---Handle result after spawn completes.
    ---@param task table Task descriptor with context
    ---@param success boolean Whether spawn succeeded
    ---@param stdout string Captured stdout (OMML)
    ---@param stderr string Captured stderr
    ---@param data DataManager Database instance
    ---@param log table Logger
    handle_result = function(task, success, stdout, stderr, data, log)
        local ctx = task.context
        local view = ctx.view

        -- Clean up temp input file
        os.remove(ctx.input_file)

        if not success then
            log.warn("Inline math conversion failed for %s: %s", tostring(view.id), stderr)
            return
        end

        local omml = stdout:gsub("%s+$", "")  -- Trim trailing whitespace
        if omml == "" then
            log.warn("Empty OMML output for inline math %s", tostring(view.id))
            return
        end

        -- Store both MathML and OMML in resolved_ast (format-agnostic)
        -- MathML for HTML output, OMML for DOCX output
        local resolved_ast = string.format('{"mathml":%q,"omml":%q}', ctx.mathml, omml)
        data:execute(Queries.content.update_view_resolved, {
            id = view.id,
            resolved = resolved_ast
        })

        log.debug("Inline math converted: %s", tostring(view.id))
    end
})

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "math_inline_handler",
    prerequisites = {"spec_views"},  -- Run AFTER spec_views clears and processes

    ---INITIALIZE: Parse inline codes, store in spec_views.raw_ast
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

    -- No on_transform - external_render_handler handles it

    ---EMIT: Render inline Code elements with math syntax.
    ---Returns format-agnostic markers; filters convert to format-specific output.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Replacement inlines
    on_render_Code = function(code, ctx)
        local expr = match_math_code(code.text or "")
        if not expr then return nil end

        local data = ctx.data
        local spec_id = ctx.spec_id or "default"
        if data and pandoc then
            -- Look up the resolved math from spec_views
            local content_key = spec_id .. ":" .. (ctx.file_seq or 0) .. ":" .. expr
            local identifier = pandoc.sha1(content_key)

            local result = data:query_one(Queries.content.view_resolved_by_id, {
                id = identifier
            })

            if result and result.resolved_ast then
                -- Parse JSON to get MathML and OMML
                local decoded = pandoc.json.decode(result.resolved_ast)
                if decoded then
                    -- Return format-agnostic markers for filter processing
                    -- Filters will pick the appropriate format:
                    -- - DOCX filter uses OMML
                    -- - HTML filter uses MathML
                    local inlines = {}
                    if decoded.omml then
                        table.insert(inlines, pandoc.RawInline("speccompiler",
                            string.format("inline-math-omml:%s", decoded.omml)))
                    end
                    if decoded.mathml then
                        table.insert(inlines, pandoc.RawInline("speccompiler",
                            string.format("inline-math-mathml:%s", decoded.mathml)))
                    end
                    if #inlines > 0 then
                        return inlines
                    end
                end
            end

            -- Fallback: Try by expression match if exact ID not found
            local fallback = data:query_one(Queries.content.view_resolved_by_expr, {
                spec_id = spec_id,
                view_type = "MATH_INLINE",
                expr = expr
            })

            if fallback and fallback.resolved_ast then
                local decoded = pandoc.json.decode(fallback.resolved_ast)
                if decoded then
                    local inlines = {}
                    if decoded.omml then
                        table.insert(inlines, pandoc.RawInline("speccompiler",
                            string.format("inline-math-omml:%s", decoded.omml)))
                    end
                    if decoded.mathml then
                        table.insert(inlines, pandoc.RawInline("speccompiler",
                            string.format("inline-math-mathml:%s", decoded.mathml)))
                    end
                    if #inlines > 0 then
                        return inlines
                    end
                end
            end
        end

        return nil
    end
}

return M
