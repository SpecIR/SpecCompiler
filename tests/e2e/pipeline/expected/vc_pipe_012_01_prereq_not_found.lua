-- Test oracle for VC-PIPE-011: prerequisite-not-found diagnostic (HLR-PIPE-011)
--
-- A prerequisite registered in ANOTHER phase is legitimate (the per-phase
-- topological sort drops it; no diagnostic). A prerequisite registered in NO
-- phase is a typo/bug and must be flagged with a prerequisite_not_found
-- diagnostic that names both the declaring handler and the missing prereq.

return function(_, _)
    local pipeline_mod = require("core.pipeline")

    local errors = {}
    local function err(m) errors[#errors + 1] = m end
    local function nop() end

    -- Mock diagnostics capturing warn(self, file, line, code, msg).
    local warnings = {}
    local diag = {
        warn = function(_, file, line, code, msg)
            warnings[#warnings + 1] = { file = file, line = line, code = code, msg = msg }
        end,
        errors = {},
        has_errors = function() return false end,
    }

    local pipeline = pipeline_mod.new({
        log = { debug = nop, info = nop, warn = nop, error = nop },
        diagnostics = diag,
    })

    -- H_init participates in INITIALIZE.
    pipeline:register_handler({ name = "H_init", on_initialize = nop })
    -- H_transform (TRANSFORM) depends on H_init in another phase: a legitimate
    -- cross-phase prerequisite -> NO diagnostic.
    pipeline:register_handler({ name = "H_transform", on_transform = nop, prerequisites = { "H_init" } })
    -- H_emit depends on a handler registered nowhere -> diagnostic.
    pipeline:register_handler({ name = "H_emit", on_emit = nop, prerequisites = { "ghost_handler" } })
    -- H_inline is a decorated per-item callback (on_render_Code, no on_<phase>
    -- hook). Its prerequisites are inert and must NOT be flagged even when they
    -- point nowhere (this is the real lof_handler shape).
    pipeline:register_handler({ name = "H_inline", on_render_Code = nop, prerequisites = { "also_ghost" } })

    pipeline:validate_prerequisites()

    -- Collect prerequisite_not_found diagnostics.
    local pnf = {}
    for _, w in ipairs(warnings) do
        if w.code == "prerequisite_not_found" then pnf[#pnf + 1] = w end
    end

    if #pnf ~= 1 then
        err(("expected exactly 1 prerequisite_not_found diagnostic, got %d"):format(#pnf))
    else
        local msg = tostring(pnf[1].msg)
        if not msg:find("ghost_handler", 1, true) then
            err("diagnostic should name the missing prereq 'ghost_handler': " .. msg)
        end
        if not msg:find("H_emit", 1, true) then
            err("diagnostic should name the declaring handler 'H_emit': " .. msg)
        end
    end

    -- The cross-phase prerequisite (H_init) must NOT be flagged, and neither
    -- must the per-item callback's inert prerequisite (also_ghost / H_inline).
    for _, w in ipairs(warnings) do
        if w.code == "prerequisite_not_found" then
            local m = tostring(w.msg)
            if m:find("H_init", 1, true) then
                err("cross-phase prerequisite H_init must not be flagged")
            end
            if m:find("also_ghost", 1, true) or m:find("H_inline", 1, true) then
                err("inert per-item-callback prerequisite must not be flagged")
            end
        end
    end

    if #errors > 0 then
        return false, "Prereq-not-found validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
