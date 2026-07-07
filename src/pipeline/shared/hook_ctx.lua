---Build the canonical contract.ctx (HLR-EXT-009) for a hook invocation.
---
---Maps the per-spec pipeline context (which carries spec_id, output_format,
---model, config, log) plus the phase-handler's data/diagnostics into the frozen
---invariant core, attaches the polymorphic `subject` and the `capability`, and
---returns a frozen ctx that is passed as the SOLE argument to a plugin hook.
---
---@module hook_ctx
local ctxmod = require("contract.ctx")
local registry = require("contract.registry")

local M = {}

-- No-op logger so a data ctx always has a callable `log` even when the data-phase
-- caller did not thread one (e.g. data_loader). Keeps `dctx.log.debug(...)` safe.
local NOOP_LOG = setmetatable({}, { __index = function() return function() end end })

---@param pctx table per-spec pipeline context (spec_id, output_format, model, config, log)
---@param data table the data manager
---@param diagnostics table the diagnostics collector
---@param subject table the polymorphic subject (object/specification/float/target/row/...)
---@param capability string which hook this is ("render"|"resolve"|"message"|...)
---@param spec_id string|nil override spec_id (defaults to pctx.spec_id); some hooks act on a
---       different spec than the loop context (e.g. an object's own specification_ref)
---@return table ctx frozen canonical context
function M.build(pctx, data, diagnostics, subject, capability, spec_id)
    pctx = pctx or {}
    return ctxmod.new({
        data = data,
        pandoc = pandoc,
        log = pctx.log,
        diagnostics = diagnostics,
        format = pctx.output_format or "docx",
        spec_id = spec_id or pctx.spec_id or "default",
        model = pctx.model or pctx.template or "default",
        config = pctx.config or {},
        subject = subject,
        capability = capability,
        host = registry.current(),
    })
end

---Build a frozen DATA ctx for a data-tier hook (dataset/build_block/transform/
---resolve/prepare_task/handle_result). Data-tier means the hook produces data,
---not presentation: no Pandoc element, no chosen output format, so the ctx
---omits pandoc/format; the hook reads its inputs off `dctx.subject.*` and the
---DB off `dctx.data`. The dispatching handler decides when it runs (RESOLVE,
---TRANSFORM, external render, or even EMIT assembly for view build_block).
---@param pctx table|nil per-spec pipeline context (log/model/config; may be sparse)
---@param data table the data manager
---@param diagnostics table|nil the diagnostics collector (optional in data phases)
---@param subject table the polymorphic subject (params/raw_content/float/target/task/...)
---@param capability string which hook this is ("dataset"|"transform"|"resolve"|...)
---@param spec_id string|nil override spec_id (defaults to pctx.spec_id)
---@return table dctx frozen data context
function M.build_data(pctx, data, diagnostics, subject, capability, spec_id)
    pctx = pctx or {}
    return ctxmod.new_data({
        data = data,
        log = pctx.log or NOOP_LOG,
        diagnostics = diagnostics,
        spec_id = spec_id or pctx.spec_id or "default",
        model = pctx.model or pctx.template or "default",
        config = pctx.config or {},
        subject = subject,
        capability = capability,
        host = registry.current(),
    })
end

return M
