---External Render Handler for SpecCompiler.
---Coordinates parallel rendering of external float and view types.
---
---Types register with prepare_task/handle_result callbacks.
---Core orchestrates: query items -> prepare tasks -> cache filter -> batch spawn -> dispatch results.
---
---Supports both:
---  - Floats (spec_floats): PlantUML, charts, block math, etc.
---  - Views (spec_views): Inline math, etc.
---
---@module external_render_handler
local M = {
    name = "external_render_handler",
    prerequisites = {"spec_floats_transform"}  -- Runs after spec_floats_transform in TRANSFORM
}

local task_runner = require("infra.process.task_runner")
local float_base = require("pipeline.shared.float_base")
local Queries = require("db.queries")

-- Registry of render callbacks by type_ref
local renderers = {}

---Register a renderer for a float type.
---@param type_ref string The type identifier (e.g., "PLANTUML", "CHART")
---@param callbacks table { prepare_task = fn(float, build_dir, log, data), handle_result = fn }
function M.register_renderer(type_ref, callbacks)
    if not callbacks.prepare_task or not callbacks.handle_result then
        error("Renderer must provide prepare_task and handle_result callbacks")
    end
    renderers[type_ref] = callbacks
end

---Check if a renderer is registered for a type.
---@param type_ref string The type identifier
---@return boolean
function M.has_renderer(type_ref)
    return renderers[type_ref] ~= nil
end

---Get the registered renderer for a type.
---@param type_ref string The type identifier
---@return table|nil callbacks or nil if not registered
function M.get_renderer(type_ref)
    return renderers[type_ref]
end

---Clear all registered renderers (for testing).
function M.clear_renderers()
    renderers = {}
end

---TRANSFORM phase: Spawn all external renders in parallel.
---Processes both floats (spec_floats) and views (spec_views).
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    local ctx = contexts[1] or {}
    local log = float_base.create_log(diagnostics)
    local build_dir = ctx.build_dir or "build"

    -- Query all floats needing external render that haven't been resolved yet
    local floats = data:query_all(Queries.content.select_floats_needing_external_render) or {}

    -- Query all views needing external render that haven't been resolved yet
    local views = data:query_all(Queries.content.select_views_needing_external_render) or {}

    local total_items = #floats + #views
    if total_items == 0 then
        log.debug("No floats or views need external rendering")
        return
    end

    log.info("Found %d items needing external rendering (%d floats, %d views)",
        total_items, #floats, #views)

    -- Phase 1: Prepare all tasks, filter cache hits
    local batch = {}
    local model_name = ctx.template or ctx.model_name or "default"

    -- Process floats
    for _, float in ipairs(floats) do
        local renderer = renderers[float.type_ref]
        if renderer and renderer.prepare_task then
            local task = renderer.prepare_task(float, build_dir, log, data, model_name)
            if task then
                -- Cache check: skip if output already exists
                if task.output_path and task_runner.file_exists(task.output_path) then
                    log.debug("Cache hit: %s (%s)", float.type_ref, tostring(float.id))
                    -- Immediately handle cached result
                    renderer.handle_result(task, true, "", "", data, log)
                else
                    task.type_ref = float.type_ref  -- Track for result dispatch
                    table.insert(batch, task)
                end
            end
        else
            log.warn("No renderer registered for float type: %s", float.type_ref)
        end
    end

    -- Process views
    for _, view in ipairs(views) do
        local renderer = renderers[view.type_ref]
        if renderer and renderer.prepare_task then
            local task = renderer.prepare_task(view, build_dir, log, data, model_name)
            if task then
                -- Cache check: skip if output already exists
                if task.output_path and task_runner.file_exists(task.output_path) then
                    log.debug("Cache hit: %s (%s)", view.type_ref, tostring(view.id))
                    -- Immediately handle cached result
                    renderer.handle_result(task, true, "", "", data, log)
                else
                    task.type_ref = view.type_ref  -- Track for result dispatch
                    table.insert(batch, task)
                end
            end
        else
            log.warn("No renderer registered for view type: %s", view.type_ref)
        end
    end

    if #batch == 0 then
        log.debug("All items resolved from cache")
        return
    end

    log.info("Spawning %d external renders in parallel", #batch)

    -- Phase 2: Spawn all in parallel using task_runner.spawn_batch
    local results = task_runner.spawn_batch(batch)

    -- Phase 3: Dispatch results to type handlers
    for _, r in ipairs(results) do
        local renderer = renderers[r.task.type_ref]
        if renderer and renderer.handle_result then
            local stdout = table.concat(r.result.stdout or {})
            local stderr = table.concat(r.result.stderr or {})
            local success = r.result.exit_code == 0
            renderer.handle_result(r.task, success, stdout, stderr, data, log)
        end
    end

    log.info("External rendering complete")
end

return M
