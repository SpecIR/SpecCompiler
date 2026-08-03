---Canonical per-call context for the Host Engine + Descriptor Plugins
---contract (HLR-EXT-009).
---
---EVERY plugin hook takes exactly ONE shallow-frozen context table as its sole
---argument, with a polymorphic `.subject` (the thing being acted on) and a
---`.capability` (which hook this is). "Frozen" here means only that top-level
---keys cannot be rebound -- the nested subject/data/config tables it points at
---remain mutable. There are TWO context flavors, selected by the hook NAME --
---the host validates the mapping (registry ALLOWED_HOOKS). The flavor decides
---WHAT the hook receives and owes, never WHEN it runs: execution time belongs
---to the phase handler that dispatches the capability (objects/specifications
---render during TRANSFORM and are persisted to the IR; floats/views render
---during EMIT; relation links rewrite during TRANSFORM; analyze messages fire
---during ANALYZE; view build_block is dispatched during EMIT assembly).
---
---  RENDER ctx -- for hooks that produce presentation output.
---    Invariant core (all asserted non-nil): data, pandoc, log, diagnostics,
---    format, spec_id, model, config; plus `host` (the registry, for cross-hook
---    dispatch). Render-tier hooks: object/specification/float/view render +
---    render_block, relation render_link, verification message. ctx.subject holds
---    e.g. { object, attributes, specification, element, float, resolved, target,
---    view_id, preset, row } depending on kind.
---
---  DATA ctx -- for hooks that produce data, not presentation; no Pandoc
---    element, no chosen format. Invariant core:
---    data, spec_id, log (pandoc/format absent; model/config/diagnostics/host ride
---    along when available). Data-tier hooks, their subject, and their ONE return:
---      view  dataset(dctx)       -> { source | data | links }   subject.params
---      view  build_block(dctx)   -> pandoc.Block                subject.params
---      float transform(dctx)     -> resolved-AST string         subject.raw_content/.float/.build_dir
---      float prepare_task(dctx)  -> task table                  subject.float/.build_dir
---      float handle_result(dctx) -> (writes resolved_ast)       subject.task/.success/.stdout/.stderr
---      reln  resolve(dctx)       -> { target, ambiguous }       subject.target_text/.source_object_id
---
---TO EXTEND: pick the hook whose NAME matches the intent (render* for output, a
---data hook above for data); you automatically receive the right context and owe
---the documented return type. `ctx:require(field)` fetches a field, erroring
---loudly on nil.

local M = {}

-- Invariant-core fields that MUST be present (non-nil) on a RENDER ctx (built
-- during the EMIT walk, where a Pandoc element is being turned into output).
M.INVARIANT_CORE = {
    "data", "pandoc", "log", "diagnostics",
    "format", "spec_id", "model", "config",
}

-- Invariant-core fields for a DATA ctx (built during the data/lifecycle phases
-- -- TRANSFORM/RESOLVE/external-render -- where there is no Pandoc element and no
-- single output format yet). pandoc/format/diagnostics/model/config ride along
-- when the caller has them but are NOT required, so a data hook never depends on
-- render-only state.
M.DATA_CORE = {
    "data", "spec_id", "log",
}

---ctx:require(field) -- fetch an invariant/declared field, erroring on nil.
---@param self table The frozen ctx
---@param field string Field name
---@return any value The non-nil value
local function ctx_require(self, field)
    if type(field) ~= "string" then
        error("ctx:require expects a field name (string), got " .. type(field), 2)
    end
    local value = self[field]
    if value == nil then
        local cap = self.capability
        local where = cap and (" (capability '" .. tostring(cap) .. "')") or ""
        error(string.format(
            "ctx:require('%s') failed: required field is nil%s", field, where), 2)
    end
    return value
end

---Shallow-freeze a field map into a read-only proxy after asserting its required
---core. Only top-level key rebinding is prevented (via __newindex); the nested
---subject/data/config tables remain mutable.
---@param fields table Field map (see module header for shape)
---@param required_core table Ordered list of field names that must be non-nil
---@param what string Label for error messages ("ctx.new"/"ctx.new_data")
---@return table ctx Shallow-frozen context
local function freeze(fields, required_core, what)
    if type(fields) ~= "table" then
        error(what .. " requires a table of fields, got " .. type(fields), 3)
    end

    -- Own a shallow copy so the caller's table is not aliased/frozen.
    local store = {}
    for k, v in pairs(fields) do store[k] = v end
    if store.subject == nil then store.subject = {} end

    local missing = {}
    for _, k in ipairs(required_core) do
        if store[k] == nil then missing[#missing + 1] = k end
    end
    if #missing > 0 then
        error(what .. ": missing core field(s): " .. table.concat(missing, ", "), 3)
    end
    if type(store.subject) ~= "table" then
        error(what .. ": subject must be a table, got " .. type(store.subject), 3)
    end

    return setmetatable({}, {
        __index = function(_, k)
            if k == "require" then return ctx_require end
            return store[k]
        end,
        -- Shallow freeze: top-level keys cannot be rebound here (nested
        -- subject/data/config tables stay mutable by design).
        __newindex = function(_, k)
            error("ctx is frozen; cannot assign field '" .. tostring(k) .. "'", 2)
        end,
        __metatable = false,  -- prevent metatable tampering
    })
end

---Build a shallow-frozen RENDER ctx (sole arg to every render-tier hook).
---@param fields table Field map (see module header for shape)
---@return table ctx Shallow-frozen canonical render context
function M.new(fields)
    return freeze(fields, M.INVARIANT_CORE, "ctx.new")
end

---Build a shallow-frozen DATA ctx (sole arg to every data-tier hook: dataset,
---build_block, transform, resolve, prepare_task, handle_result).
---@param fields table Field map (data/spec_id/log required; subject polymorphic)
---@return table ctx Shallow-frozen data context
function M.new_data(fields)
    return freeze(fields, M.DATA_CORE, "ctx.new_data")
end

return M
