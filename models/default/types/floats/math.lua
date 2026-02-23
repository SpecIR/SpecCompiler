---Math type module for SpecCompiler.
---Handles AsciiMath to MathML to OMML conversion for block math floats.
---Uses external_render_handler for parallel batch MathML→OMML conversion.
---
---@module math
local task_runner = require("infra.process.task_runner")
local external_render = require("pipeline.transform.external_render_handler")
local math_utils = require("pipeline.shared.math_render_utils")
local Queries = require("db.queries")

local M = {}

M.float = {
    id = "MATH",
    long_name = "Math",
    description = "A mathematical expression (AsciiMath)",
    caption_format = "Equation",
    counter_group = "EQUATION",  -- Own counter for equations
    aliases = { "math", "asciimath", "equation", "eq" },
    style_id = "MATH",
    needs_external_render = true,  -- Enable batch processing via external_render_handler
}

-- ============================================================================
-- External Render Registration (parallel batch processing)
-- ============================================================================

external_render.register_renderer("MATH", {
    ---Prepare a spawn task for MathML→OMML conversion.
    ---@param float table Float record from database
    ---@param build_dir string Build directory path
    ---@param log table Logger
    ---@param data DataManager Database instance
    ---@param model_name string Model name
    ---@return table|nil task Task descriptor or nil to skip
    prepare_task = function(float, build_dir, log, data, model_name)
        -- First convert AsciiMath → MathML
        local mathml, err = math_utils.asciimath_to_mathml(float.raw_content, "block")
        if not mathml then
            log.warn("Failed to convert AsciiMath for %s: %s", tostring(float.id), err or "unknown")
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

        log.info("Preparing math conversion: %s", hash:sub(1, 12))

        local cmd, args = math_utils.build_render_command(render_script, is_compiled, input_file)

        return {
            cmd = cmd,
            args = args,
            opts = { timeout = 10000 },
            context = {
                hash = hash,
                float = float,
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
        local float = ctx.float

        -- Clean up temp input file
        os.remove(ctx.input_file)

        if not success then
            log.warn("Math conversion failed for %s: %s", tostring(float.id), stderr)
            return
        end

        local omml = stdout:gsub("%s+$", "")  -- Trim trailing whitespace
        if omml == "" then
            log.warn("Empty OMML output for %s", tostring(float.id))
            return
        end

        -- Store both MathML and OMML in resolved_ast (format-agnostic)
        -- MathML for HTML output, OMML for DOCX output
        local resolved_ast = string.format('{"mathml":%q,"omml":%q}', ctx.mathml, omml)
        data:execute(Queries.content.update_float_resolved, {
            id = float.id,
            ast = resolved_ast
        })

        log.debug("Math converted: %s", tostring(float.id))
    end
})

-- ============================================================================
-- Handler
-- ============================================================================

-- Note: dkjson is used for decoding simple JSON (not Pandoc AST)
local dkjson = require("dkjson")

M.handler = {
    name = "math_handler",
    prerequisites = {},
    -- No on_transform - external_render_handler does the work

    ---EMIT: Convert resolved_ast to Pandoc elements.
    ---@param block table Pandoc CodeBlock element
    ---@param ctx table Context with data, spec_id, log, preset
    ---@param float table Float record from database
    ---@param resolved string resolved_ast JSON string
    ---@return table|nil Pandoc element or nil
    on_render_CodeBlock = function(block, ctx, float, resolved)
        if not resolved or not pandoc then return nil end

        -- Parse our resolved_ast format: {"mathml":"...", "omml":"..."}
        local math_data, pos, err = dkjson.decode(resolved)
        if not math_data or (not math_data.omml and not math_data.mathml) then
            return nil
        end

        -- Get caption config for equation numbering
        local float_base = require("pipeline.shared.float_base")
        local math_config = float_base.get_caption_config("MATH", ctx.preset)
        local seq_name = math_config.seq_name or "Equation"

        -- Build format-agnostic content blocks
        -- Filters will convert to format-specific output (DOCX uses OMML, HTML uses MathML)
        local content_blocks = {}
        if math_data.omml then
            table.insert(content_blocks, pandoc.RawBlock("speccompiler",
                string.format("math-omml:%s", math_data.omml)))
        end
        if math_data.mathml then
            table.insert(content_blocks, pandoc.RawBlock("speccompiler",
                string.format("math-mathml:%s", math_data.mathml)))
        end

        -- Wrap in semantic Div for filter processing
        return pandoc.Div(
            content_blocks,
            pandoc.Attr("", {"speccompiler-numbered-equation"}, {
                ["seq-name"] = seq_name,
                ["number"] = tostring(float.number or ""),
                ["identifier"] = float.anchor or float.label or "",
            })
        )
    end
}

return M
