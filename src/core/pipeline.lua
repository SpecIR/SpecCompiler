---Pipeline Orchestrator for SpecCompiler.
---Simplified 5-phase lifecycle with context propagation.
---Supports declarative handler prerequisites with topological sorting.

local M = {}

-- For timing handler execution
local uv = require("luv")

M.PHASES = {
    INITIALIZE = "initialize",
    RESOLVE    = "resolve",
    ANALYZE    = "analyze",
    TRANSFORM  = "transform",
    EMIT       = "emit"
}

function M.new(opts)
    local self = setmetatable({}, { __index = M })
    self.log = opts.log
    self.diagnostics = opts.diagnostics
    self.data = opts.data
    self.validation = opts.validation  -- Validation policy from project.yaml
    self.project_info = opts.project_info  -- Full project info (template, files, etc.)
    self.handlers = {}  -- name -> handler

    return self
end

---Register a handler with prerequisites.
---
---A handler is a phase handler: it defines one or more `on_<phase>` hooks
---(e.g. `on_transform`) and relies on `prerequisites` to order itself against
---other phase handlers. `prerequisites` is optional and defaults to an empty
---list.
---@param handler table Handler with name field, optional prerequisites array, and on_{phase} hooks
function M:register_handler(handler)
    if not handler.name then
        error("Handler must have a 'name' field")
    end
    if self.handlers[handler.name] then
        error("Handler already registered: " .. handler.name)
    end

    handler.prerequisites = handler.prerequisites or {}
    self.handlers[handler.name] = handler

    if self.log then self.log.debug("Registered handler: " .. handler.name) end
end

---Validate declared prerequisites once all handlers are registered (HLR-PIPE-008).
---
---The per-phase topological sort deliberately drops a prerequisite that does
---not participate in the current phase, because handlers cannot be ordered
---across phases. That filter conflates two cases: a prerequisite registered in
---ANOTHER phase (legitimate) and one registered in NO phase (a typo/bug). This
---pass distinguishes them, emitting a diagnostic only for the latter. The
---cross-phase filter itself is untouched.
function M:validate_prerequisites()
    -- A prerequisite only constrains ordering for handlers that participate in
    -- a phase (declare an on_<phase> hook). Non-phase handlers are skipped:
    -- their prerequisites are inert and are not validated -- flagging them
    -- would be noise.
    local function is_phase_handler(handler)
        for _, phase in pairs(M.PHASES) do
            if handler["on_" .. phase] then return true end
        end
        return false
    end

    local names = {}
    for name in pairs(self.handlers) do names[#names + 1] = name end
    table.sort(names)  -- deterministic diagnostic order

    for _, name in ipairs(names) do
        local handler = self.handlers[name]
        if is_phase_handler(handler) then
            for _, prereq in ipairs(handler.prerequisites or {}) do
                if not self.handlers[prereq] then
                    local msg = ("handler '%s' declares prerequisite '%s' which is not "
                        .. "registered in any phase"):format(name, prereq)
                    if self.diagnostics and self.diagnostics.warn then
                        self.diagnostics:warn("pipeline", 0, "prerequisite_not_found", msg)
                    elseif self.log then
                        self.log.warn("[PIPELINE] " .. msg)
                    end
                end
            end
        end
    end
end

---Topological sort of handlers for a given phase
---Returns ordered list of handler names, or errors on cycle
---@param phase_name string Phase to sort handlers for
---@return table Ordered list of handler names
function M:topological_sort(phase_name)
    local hook = "on_" .. phase_name

    -- Find handlers that participate in this phase
    local participants = {}
    for name, handler in pairs(self.handlers) do
        if handler[hook] then
            participants[name] = true
        end
    end

    -- Build dependency graph (only for participants)
    local graph = {}  -- name -> {prereq1, prereq2, ...}
    for name in pairs(participants) do
        local handler = self.handlers[name]
        local prereqs = handler.prerequisites or {}
        graph[name] = {}
        for _, prereq in ipairs(prereqs) do
            -- Only include prereqs that participate in this phase
            if participants[prereq] then
                table.insert(graph[name], prereq)
            end
        end
    end

    -- Kahn's algorithm for topological sort
    local in_degree = {}
    for name in pairs(graph) do
        in_degree[name] = 0
    end
    for name, prereqs in pairs(graph) do
        for _ in ipairs(prereqs) do
            in_degree[name] = (in_degree[name] or 0) + 1
        end
    end

    -- Find nodes with no dependencies
    local queue = {}
    for name, degree in pairs(in_degree) do
        if degree == 0 then
            table.insert(queue, name)
        end
    end

    -- Sort alphabetically for deterministic output
    table.sort(queue)

    local sorted = {}
    while #queue > 0 do
        local name = table.remove(queue, 1)
        table.insert(sorted, name)

        -- Reduce in-degree for dependents
        for dependent, prereqs in pairs(graph) do
            for _, prereq in ipairs(prereqs) do
                if prereq == name then
                    in_degree[dependent] = in_degree[dependent] - 1
                    if in_degree[dependent] == 0 then
                        table.insert(queue, dependent)
                    end
                end
            end
        end

        -- Keep sorted for determinism
        table.sort(queue)
    end

    -- Check for cycles
    local graph_size = 0
    for _ in pairs(graph) do graph_size = graph_size + 1 end

    if #sorted < graph_size then
        -- Find cycle for error message
        local remaining = {}
        for name in pairs(graph) do
            local found = false
            for _, s in ipairs(sorted) do
                if s == name then found = true; break end
            end
            if not found then
                table.insert(remaining, name)
            end
        end
        error("Circular dependency detected in handlers: " .. table.concat(remaining, ", "))
    end

    return sorted
end

function M:run_phase(phase_name, contexts)
    -- Use uv.hrtime() for accurate timing (returns nanoseconds, works without event loop)
    local phase_start = uv.hrtime()
    local ctx_count = contexts and #contexts or 0
    if self.log then
        self.log.info("Running phase: %s (%d context(s))", phase_name, ctx_count)
    end

    local sorted = self:topological_sort(phase_name)
    local hook = "on_" .. phase_name

    for _, name in ipairs(sorted) do
        local handler = self.handlers[name]
        local handler_start = uv.hrtime()
        if self.log then
            self.log.debug("  Running handler: %s", name)
        end

        handler[hook](self.data, contexts, self.diagnostics)

        local handler_duration = (uv.hrtime() - handler_start) / 1e6  -- ns -> ms
        if self.log then
            self.log.debug("  Completed handler: %s (%.1fms)", name, handler_duration)
        end
    end

    local phase_duration = (uv.hrtime() - phase_start) / 1e6  -- ns -> ms
    if self.log then
        self.log.debug("Phase %s completed in %.1fms", phase_name, phase_duration)
    end
end

---Execute the pipeline for all documents.
---@param docs table Array of DocumentWalker objects
---@param opts table|nil Options: { skip_phases = { "initialize", "analyze", ... } }
function M:execute(docs, opts)
    opts = opts or {}
    local skip_phases = {}
    for _, phase in ipairs(opts.skip_phases or {}) do
        skip_phases[phase] = true
    end

    -- All handlers are registered by now; flag any prerequisite that resolves
    -- to no registered handler in any phase (HLR-PIPE-008).
    self:validate_prerequisites()

    local contexts = {}
    local pinfo = self.project_info or {}
    local docx_info = pinfo.docx or {}

    -- Resolve reference_doc path (make absolute if relative)
    local reference_doc = docx_info.reference_doc
    -- AUTO-WIRE: If no explicit reference_doc but preset exists, use default location
    if not reference_doc and docx_info.preset then
        local output_dir = pinfo.output_dir or "build"
        reference_doc = output_dir .. "/reference.docx"
    end
    if reference_doc and not reference_doc:match("^/") then
        local project_root = pinfo.project_root or "."
        reference_doc = project_root .. "/" .. reference_doc
    end

    -- Build base context (shared by all documents)
    local base_ctx = {
        validation = self.validation,  -- Validation policy from project.yaml
        build_dir = pinfo.output_dir or "build",
        log = self.log,  -- Logger for backend handlers
        output_format = pinfo.output_format or "docx",
        template = pinfo.template or "default",  -- Template name for model loading
        -- DOCX-specific context (for styles and postprocessing)
        reference_doc = reference_doc,  -- Path to generated reference.docx with custom styles
        docx = docx_info,  -- Full DOCX config from project.yaml
        project_root = pinfo.project_root or ".",  -- For resolving relative paths
        db_file = pinfo.db_file,  -- SPEC-IR database path (postprocessor metadata queries)
        -- Multi-format output support
        outputs = pinfo.outputs,  -- Array of {format, path} from project.yaml
        html5 = pinfo.html5,  -- HTML5 config from project.yaml
        latex = pinfo.latex,  -- LaTeX config from project.yaml
        -- Bibliography/citation configuration
        bibliography = pinfo.bibliography,  -- Path to .bib file
        -- Canonical contract.ctx invariant-core inputs (HLR-EXT-009): the active
        -- model name and a frozen project-config slice, threaded so every hook
        -- dispatch site can build the canonical ctx.
        model = pinfo.template or "default",
    }
    base_ctx.config = {
        build_dir = base_ctx.build_dir,
        project_root = base_ctx.project_root,
        reference_doc = reference_doc,
        docx = docx_info,
        html5 = pinfo.html5,
        latex = pinfo.latex,
        validation = self.validation,
        bibliography = pinfo.bibliography,
        output_format = base_ctx.output_format,
        log_level = (pinfo.logging or {}).level,
    }

    -- Debug: Log bibliography configuration
    if pinfo.bibliography then
        self.log.debug("[PIPELINE] Bibliography configured: %s", pinfo.bibliography)
    end

    for _, doc in ipairs(docs) do
        -- Bundle document with base context
        local ctx = {}
        for k, v in pairs(base_ctx) do ctx[k] = v end
        ctx.doc = doc
        ctx.spec_id = doc.spec_id or "default"
        table.insert(contexts, ctx)
    end

    -- Build emit_contexts: dirty docs + cached docs.
    -- EMIT phase needs contexts for ALL spec_ids so it can check output cache
    -- and regenerate missing outputs even for cached (unchanged) documents.
    local cached_spec_ids = opts.cached_spec_ids or {}
    local emit_contexts = {}
    for _, ctx in ipairs(contexts) do
        table.insert(emit_contexts, ctx)
    end
    for _, spec_id in ipairs(cached_spec_ids) do
        local ctx = {}
        for k, v in pairs(base_ctx) do ctx[k] = v end
        ctx.spec_id = spec_id
        ctx.doc = nil
        ctx.cached = true
        table.insert(emit_contexts, ctx)
    end

    if not skip_phases[M.PHASES.INITIALIZE] then
        self:run_phase(M.PHASES.INITIALIZE, contexts)
    end
    if not skip_phases[M.PHASES.RESOLVE] then
        self:run_phase(M.PHASES.RESOLVE, contexts)
    end
    if not skip_phases[M.PHASES.TRANSFORM] then
        self:run_phase(M.PHASES.TRANSFORM, contexts)
    end
    if not skip_phases[M.PHASES.ANALYZE] then
        self:run_phase(M.PHASES.ANALYZE, emit_contexts)
    end

    -- Abort if analysis found errors
    -- ANALYZE runs after TRANSFORM so analyze queries can check transform results
    -- (e.g., float render failure, view materialization failure)
    if self.diagnostics and self.diagnostics:has_errors() then
        if self.log then
            self.log.error("Pipeline aborted: analysis found %d error(s)", #self.diagnostics.errors)
        end
        return  -- Don't continue to EMIT phase
    end

    if not skip_phases[M.PHASES.EMIT] then
        self:run_phase(M.PHASES.EMIT, emit_contexts)
    end
end

return M
