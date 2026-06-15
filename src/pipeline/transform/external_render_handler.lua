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
local logger = require("infra.logger")
local Queries = require("db.queries")
local hook_ctx = require("pipeline.shared.hook_ctx")

local registry = require("contract.registry")

---Resolve the external renderer for a type from the host's hook index. A
---type is either a float or a view; both prepare_task and handle_result must be
---present for it to count as a renderer.
---@param type_ref string The type identifier (e.g., "PLANTUML", "CHART")
---@return table|nil { prepare_task, handle_result } or nil
local function host_renderer(type_ref)
    local host = registry.current()
    if not host or not type_ref then return nil end
    local tr = type_ref:upper()
    for _, kind in ipairs({ "float", "view" }) do
        -- Inherited lookup: a float extending an external float (e.g. a
        -- SEQUENCE extending PLANTUML) inherits the prepare/handle pair.
        local prepare = host:get_hook_inherited(kind, tr, "prepare_task")
        local handle = host:get_hook_inherited(kind, tr, "handle_result")
        if prepare and handle then
            return { prepare_task = prepare, handle_result = handle }
        end
    end
    return nil
end

---TRANSFORM phase: Spawn all external renders in parallel.
---Processes both floats (spec_floats) and views (spec_views).
---@param data DataManager
---@param contexts Context[]
---@param diagnostics Diagnostics
function M.on_transform(data, contexts, diagnostics)
    local ctx = contexts[1] or {}
    local log = logger.create_diagnostic_adapter(diagnostics, "FLOAT")
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

    -- Build the small DATA ctx the external-render hooks take: the render target
    -- (float/view record) + build_dir for prepare_task; the spawn result for
    -- handle_result. data/log/model ride on the ctx core.
    local function prep_ctx(record)
        return hook_ctx.build_data({ log = log, model = model_name }, data, diagnostics,
            { float = record, build_dir = build_dir }, "prepare_task", record.specification_ref)
    end
    local function result_ctx(task, success, stdout, stderr)
        return hook_ctx.build_data({ log = log, model = model_name }, data, diagnostics,
            { task = task, success = success, stdout = stdout, stderr = stderr }, "handle_result")
    end

    -- Prepare tasks for floats and views (identical handling; only the warn label differs)
    local function process_items(items, kind_label)
        for _, item in ipairs(items) do
            local renderer = host_renderer(item.type_ref)
            if renderer then
                local task = renderer.prepare_task(prep_ctx(item))
                if task then
                    -- Cache check: skip if output already exists
                    if task.output_path and task_runner.file_exists(task.output_path) then
                        log.debug("Cache hit: %s (%s)", item.type_ref, tostring(item.id))
                        -- Immediately handle cached result
                        renderer.handle_result(result_ctx(task, true, "", ""))
                    else
                        task.type_ref = item.type_ref  -- Track for result dispatch
                        table.insert(batch, task)
                    end
                end
            else
                log.warn("No renderer registered for %s type: %s", kind_label, item.type_ref)
            end
        end
    end
    process_items(floats, "float")
    process_items(views, "view")

    if #batch == 0 then
        log.debug("All items resolved from cache")
        return
    end

    log.info("Spawning %d external renders in parallel", #batch)

    -- Phase 2: Spawn all in parallel using task_runner.spawn_batch
    local results = task_runner.spawn_batch(batch)

    -- Phase 3: Dispatch results to type handlers
    for _, r in ipairs(results) do
        local renderer = host_renderer(r.task.type_ref)
        if renderer then
            local stdout = table.concat(r.result.stdout or {})
            local stderr = table.concat(r.result.stderr or {})
            local success = r.result.exit_code == 0
            renderer.handle_result(result_ctx(r.task, success, stdout, stderr))
        end
    end

    log.info("External rendering complete")
end

return M
