---Emitter Handler for SpecCompiler.
---Format-agnostic orchestrator for document output via Pandoc.
---Handles docx, html5, markdown, json formats via config.outputs array.
---
---Uses the correct architecture:
---  1. Assemble Pandoc document from IR database (via assembler)
---  2. Run float resolution (render PlantUML, charts, etc.)
---  3. Use OutputWriter to write via Pandoc CLI
---  4. Postprocessor handles template-specific modifications
---
---Note: ReqIF export is no longer handled here. Use the standalone
---`python -m reqif.specir` CLI for ReqIF ↔ SpecIR interoperability.
---
---@module emitter
local Writer = require("infra.format.writer")
local Assembler = require("pipeline.emit.assembler")
local OutputCache = require("db.output_cache")
local pandoc_cli = require("infra.process.pandoc_cli")
local task_runner = require("infra.process.task_runner")
local hash_utils = require("infra.hash_utils")

-- Helper modules (extracted from this file)
local float_resolver = require("pipeline.emit.float_resolver")
local emit_float = require("pipeline.emit.emit_float")
local emit_view = require("pipeline.emit.emit_view")

local M = {
    name = "emitter",
    prerequisites = {"fts_indexer"}  -- Runs after FTS indexer
}

local function get_log_from_contexts(contexts)
    return contexts[1].log or {
        debug = function() end,
        info = function() end,
        error = function() end,
        warn = function() end
    }
end

local function load_docx_preset(ctx, log)
    if not ctx.template then
        return nil
    end

    local preset_loader = require("infra.format.docx.preset_loader")
    local speccompiler_home = pandoc_cli.get_speccompiler_home()
    local explicit_preset = ctx.docx and ctx.docx.preset
    local preset_name = explicit_preset or "default"
    local preset = preset_loader.load_with_extends(speccompiler_home, ctx.template, preset_name)
    if preset then
        log.debug("Loaded preset: %s/%s from %s", ctx.template, preset_name, speccompiler_home)
    elseif explicit_preset then
        log.warn("Failed to load preset: %s/%s from %s", ctx.template, preset_name, speccompiler_home)
    else
        log.debug("No preset found for %s (using defaults)", ctx.template)
    end
    return preset
end

local function collect_documents(data, contexts, log, diagnostics)
    local documents = {}

    -- Preset and float resolution are context-invariant: hoisted out of the
    -- per-document loop (floats resolve globally, preset comes from base ctx).
    local preset = contexts[1] and load_docx_preset(contexts[1], log) or nil
    local float_results = float_resolver.resolve_floats(data, log)

    for _, c in ipairs(contexts) do
        local output_dir = c.build_dir or "build"
        local spec_id = c.spec_id or "default"
        local output_path = c.output_path or (output_dir .. "/" .. spec_id .. ".docx")

        log.debug("Assembling document for %s...", spec_id)
        local doc = Assembler.assemble_document(data, spec_id, log)
        if not doc or (doc.blocks and #doc.blocks == 0) then
            doc = c.doc and c.doc.doc
        end

        if not doc then
            log.warn("No document available for %s", spec_id)
            goto continue_context
        end

        local transformed_doc = emit_float.transform_floats_in_doc(doc, float_results, data, spec_id, log, preset, c, diagnostics)
        transformed_doc = emit_view.transform_views_in_doc(transformed_doc, data, spec_id, log, c, diagnostics)

        local config = c.config or {}
        config.output_dir = output_dir
        config.project_root = c.project_root or "."
        config.template = c.template
        config.db_file = c.db_file
        config.outputs = c.outputs
        config.html5 = c.html5
        config.latex = c.latex
        config.docx = c.docx
        config.bibliography = c.bibliography

        documents[#documents + 1] = {
            doc = transformed_doc,
            out_path = output_path,
            config = config,
            spec_id = spec_id,
            ctx = c,
            reference_doc = c.reference_doc
        }

        ::continue_context::
    end

    return documents
end

local function build_format_config(d, output, log)
    local format_config = d.config[output.format] or {}

    if output.format == "docx" and d.reference_doc and not format_config.reference_doc then
        format_config = { reference_doc = d.reference_doc }
        for k, v in pairs(d.config[output.format] or {}) do
            format_config[k] = v
        end
    end

    if output.format == "docx" and not format_config.resource_path then
        format_config.resource_path = d.config.output_dir or "build"
    end

    if d.config.bibliography and not format_config.bibliography then
        format_config.bibliography = d.config.bibliography
        log.debug("[EMIT] Merged bibliography: %s", d.config.bibliography)
    end
    return format_config
end

local function resolve_project_path(path, project_root)
    if not path then
        return nil
    end
    if path:match("^/") then
        return path
    end
    return (project_root or ".") .. "/" .. path
end

local function collect_output_dependencies(d)
    local deps = {}
    local project_root = d.config.project_root or "."

    local bibliography = resolve_project_path(d.config.bibliography, project_root)
    if bibliography then
        deps[#deps + 1] = bibliography
    end

    local latex = d.config.latex or {}
    local uspsc_zip = resolve_project_path(latex.uspsc_zip, project_root)
    if uspsc_zip then
        deps[#deps + 1] = uspsc_zip
    end

    return deps
end

---Prepare one pandoc task for a single (document, output) pair: cache check,
---per-format filter, filtered-AST serialization, and task construction.
---@param d table Document bundle ({doc, spec_id, config, ...})
---@param output table Output spec ({format, path}) from project.yaml
---@param json_dir string Directory for serialized ASTs
---@param output_cache table OutputCache instance
---@param log table Logger adapter
---@return table|nil task Pandoc task, or nil when skipped/failed
---@return table|nil meta {spec_id, format, output_path} when task is returned
---@return string|nil format_json_path Saved filtered-AST path (independent of task)
local function prepare_output_task(d, output, json_dir, output_cache, log)
    local output_path = output.path:gsub("{spec_id}", d.spec_id)

    local work_doc = d.doc
    local filter = Writer.load_filter(d.config.template, output.format)
    if filter and filter.apply then
        local filter_ok, filtered = pcall(filter.apply, d.doc, d.config, log)
        if filter_ok and filtered then
            work_doc = filtered
            log.debug("[EMIT] Applied filter: %s/%s", d.config.template or "default", output.format)
        else
            log.warn("[EMIT] Filter error for %s: %s", output.format, tostring(filtered))
        end
    end

    local format_json_path = json_dir .. "/" .. d.spec_id .. "_" .. output.format .. ".json"
    local filter_json_ok, filter_doc_json = pcall(function()
        return pandoc.write(work_doc, "json")
    end)
    if not filter_json_ok then
        log.error("Failed to serialize %s document %s to JSON: %s", output.format, d.spec_id, tostring(filter_doc_json))
        return nil
    end

    -- Cache key = hash of the exact pandoc input just serialized. Whatever
    -- changed the rendered document (cross-doc view data, template filter
    -- edits, own content) is captured here by construction.
    local input_hash = hash_utils.sha1(filter_doc_json)

    local deps = collect_output_dependencies(d)
    if output.format == "docx" and d.reference_doc then
        deps[#deps + 1] = d.reference_doc
    end

    if output_cache:is_output_current(d.spec_id, output_path, deps, input_hash) then
        log.info("Skipped %s: %s (unchanged)", output.format, output_path)
        return nil
    end

    local output_dir = output_path:match("^(.+)/[^/]+$")
    if output_dir then
        task_runner.ensure_dir(output_dir)
    end

    local format_config = build_format_config(d, output, log)

    -- The task always references format_json_path (matching prior behavior even
    -- when the write fails — pandoc then reports the missing input itself);
    -- only the RETURNED path is nil'd so the caller's saved-AST list stays accurate.
    local saved_json_path = format_json_path
    local filter_write_ok, filter_write_err = task_runner.write_file(format_json_path, filter_doc_json)
    if not filter_write_ok then
        log.warn("Failed to save filtered Pandoc AST: %s", filter_write_err or "unknown")
        saved_json_path = nil
    end

    local task = pandoc_cli.build_task(
        output.format,
        format_config,
        format_json_path,
        output_path,
        d.config.project_root,
        d.config.template or "default",
        {
            spec_id = d.spec_id,
            format = output.format,
            output_path = output_path
        }
    )

    if task.args then
        log.debug("[EMIT] Pandoc args for %s: %s", output.format, table.concat(task.args, " "))
    end

    return task, {
        spec_id = d.spec_id,
        format = output.format,
        output_path = output_path,
        input_hash = input_hash
    }, saved_json_path
end

local function prepare_emit_tasks(documents, output_cache, diagnostics, log)
    local tasks = {}
    local task_metadata = {}
    local format_json_paths = {}

    log.debug("[EMIT] on_emit called with %d document(s) in this batch", #documents)

    for _, d in ipairs(documents) do
        local outputs = d.config.outputs or { { format = "docx", path = d.out_path } }

        log.debug("[EMIT] spec_id=%s, outputs count=%d", d.spec_id, #outputs)
        for i, o in ipairs(outputs) do
            log.debug("[EMIT]   output[%d]: format=%s, path=%s", i, o.format or "nil", o.path or "nil")
        end

        local json_ok, doc_json = pcall(function()
            return pandoc.write(d.doc, "json")
        end)
        if not json_ok then
            log.error("Failed to serialize document %s to JSON: %s", d.spec_id, tostring(doc_json))
            if diagnostics then
                diagnostics:error(nil, nil, "EMIT", string.format(
                    "Document serialization failed for %s: %s",
                    d.spec_id, tostring(doc_json)
                ))
            end
            goto continue_doc
        end

        local json_dir = (d.config.output_dir or "build") .. "/json"
        task_runner.ensure_dir(json_dir)
        local json_path = json_dir .. "/" .. d.spec_id .. ".json"
        local write_ok, write_err = task_runner.write_file(json_path, doc_json)
        if write_ok then
            log.debug("Saved Pandoc AST: %s", json_path)
        else
            log.warn("Failed to save Pandoc AST: %s", write_err or "unknown")
        end

        for _, output in ipairs(outputs) do
            local task, meta, format_json_path =
                prepare_output_task(d, output, json_dir, output_cache, log)
            if task then
                tasks[#tasks + 1] = task
                task_metadata[#task_metadata + 1] = meta
            end
            if format_json_path then
                format_json_paths[#format_json_paths + 1] = format_json_path
            end
        end

        ::continue_doc::
    end

    return tasks, task_metadata, format_json_paths
end

local function process_emit_results(results, task_metadata, output_cache, diagnostics, log)
    local outputs_by_format = {}

    for i, result in ipairs(results) do
        local meta = task_metadata[i]
        local stderr = table.concat(result.result.stderr or {})
        local success = result.result.exit_code == 0

        if success then
            output_cache:update_cache(meta.spec_id, meta.output_path, meta.input_hash)
            log.info("Generated %s: %s", meta.format, meta.output_path)

            local fmt = meta.format
            if not outputs_by_format[fmt] then
                outputs_by_format[fmt] = { paths = {} }
            end
            outputs_by_format[fmt].paths[#outputs_by_format[fmt].paths + 1] = meta.output_path
        else
            log.error("Failed to generate %s for %s: exit_code=%d",
                meta.format, meta.spec_id, result.result.exit_code or -1)
            if stderr and stderr ~= "" then
                log.error("Pandoc stderr: %s", stderr)
            end
            if diagnostics then
                diagnostics:error(nil, nil, "EMIT", string.format(
                    "%s generation failed for %s (exit %d): %s",
                    meta.format:upper(), meta.spec_id,
                    result.result.exit_code or -1, stderr
                ))
            end
        end
    end

    return outputs_by_format
end

local function cleanup_intermediate_json(format_json_paths, log)
    for _, json_path in ipairs(format_json_paths) do
        os.remove(json_path)
    end
    if #format_json_paths > 0 then
        log.debug("[EMIT] Cleaned up %d intermediate JSON files", #format_json_paths)
    end
end

local function finalize_postprocessors(outputs_by_format, contexts, log)
    local template = contexts[1] and contexts[1].template or "default"
    local project_root = contexts[1] and contexts[1].project_root or "."

    local function wants_format(fmt)
        local outs = contexts[1] and contexts[1].outputs
        if type(outs) ~= "table" then
            return false
        end
        for _, o in ipairs(outs) do
            local f = o and o.format
            if f == fmt then
                return true
            end
        end
        return false
    end

    local function output_paths_for_format(fmt)
        local paths = {}
        local ctx = contexts[1] or {}
        local outs = ctx.outputs
        if type(outs) ~= "table" then
            return paths
        end
        local output_dir = ctx.build_dir or "build"
        local spec_id = ctx.spec_id or "default"
        for _, o in ipairs(outs) do
            if o and o.format == fmt and o.path then
                local path = o.path:gsub("{spec_id}", spec_id)
                if not path:match("^/") and not path:match("/") then
                    path = output_dir .. "/" .. path
                end
                paths[#paths + 1] = path
            end
        end
        return paths
    end

    local function build_finalize_config()
        local output_dir = contexts[1].build_dir or "build"
        local finalize_config = {
            template = template,
            project_root = project_root,
            output_dir = output_dir,
            db_path = contexts[1].db_file or (output_dir .. "/specir.db"),
        }
        local ctx_config = contexts[1] and contexts[1].config or {}
        for k, v in pairs(ctx_config) do
            if finalize_config[k] == nil then
                finalize_config[k] = v
            end
        end
        local ctx = contexts[1] or {}
        finalize_config.spec_id = ctx.spec_id
        finalize_config.bibliography = ctx.bibliography
        finalize_config.latex = ctx.latex
        finalize_config.docx = ctx.docx
        return finalize_config
    end

    for fmt, info in pairs(outputs_by_format) do
        local writer_fmt = fmt
        if fmt == "html" then
            writer_fmt = "html5"
        end

        local postprocessor = Writer.load_postprocessor(template, writer_fmt)
        if postprocessor and postprocessor.finalize then
            local finalize_config = build_finalize_config()

            local ok, err = pcall(postprocessor.finalize, info.paths, finalize_config, log)
            if ok then
                log.info("[EMIT] Finalized %s postprocessor (%d files)", fmt, #info.paths)
            else
                log.warn("[EMIT] Finalize error for %s: %s", fmt, tostring(err))
            end
        end
    end

    -- PDF generation is a LaTeX postprocessor side effect. If the TeX output is
    -- cache-hit, run the postprocessor over the existing TeX file so configured
    -- PDF compilation still happens.
    if not outputs_by_format.latex and wants_format("latex") then
        local postprocessor = Writer.load_postprocessor(template, "latex")
        if postprocessor and postprocessor.finalize then
            local paths = output_paths_for_format("latex")
            local ok, err = pcall(postprocessor.finalize, paths, build_finalize_config(), log)
            if ok then
                log.info("[EMIT] Finalized latex postprocessor on cached output (%d files)", #paths)
            else
                log.warn("[EMIT] Finalize error for latex (cached build): %s", tostring(err))
            end
        end
    end

    -- Even when all documents are cached and no outputs were regenerated,
    -- we still want to re-run HTML finalization so UI/asset changes
    -- (CSS/JS/templates) are reflected in index.html.
    if not outputs_by_format.html5 and not outputs_by_format.html and wants_format("html5") then
        local postprocessor = Writer.load_postprocessor(template, "html5")
        if postprocessor and postprocessor.finalize then
            local output_dir = contexts[1].build_dir or "build"
            local finalize_config = {
                template = template,
                project_root = project_root,
                output_dir = output_dir,
                db_path = output_dir .. "/specir.db",
            }

            local ok, err = pcall(postprocessor.finalize, {}, finalize_config, log)
            if ok then
                log.info("[EMIT] Finalized html5 postprocessor (cached build)")
            else
                log.warn("[EMIT] Finalize error for html5 (cached build): %s", tostring(err))
            end
        end
    end
end

-- ============================================================================
-- Pipeline Handler
-- ============================================================================

---Unified pipeline hook for the EMIT phase.
---Handles both single document and batch (multiple document) cases.
---Format-agnostic batch emitter: outputs docx, html5, markdown, json based on config.outputs.
---Processes ALL documents in parallel for maximum throughput.
---@param data DataManager
---@param contexts table[] Array of contexts (one per document) - batch mode
---@param diagnostics table Diagnostics collector
function M.on_emit(data, contexts, diagnostics)
    if not contexts or #contexts == 0 then
        return
    end

    local log = get_log_from_contexts(contexts)
    local output_cache = OutputCache.new(data, log)

    local documents = collect_documents(data, contexts, log, diagnostics)
    if #documents == 0 then
        log.debug("No documents to generate")
        return
    end

    local tasks, task_metadata, format_json_paths = prepare_emit_tasks(documents, output_cache, diagnostics, log)

    local outputs_by_format = {}

    if #tasks > 0 then
        log.info("Spawning %d pandoc processes in parallel", #tasks)
        local results = task_runner.spawn_batch(tasks)
        outputs_by_format = process_emit_results(results, task_metadata, output_cache, diagnostics, log)
        cleanup_intermediate_json(format_json_paths, log)
    end

    finalize_postprocessors(outputs_by_format, contexts, log)
end

return M
