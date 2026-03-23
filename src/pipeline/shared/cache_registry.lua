---Cache registry for SpecCompiler.
---Centralizes module-level cache clearing for re-entrant engine.run_project calls.
---
---Each handler with module-level caches registers its clear function at require-time.
---engine.lua calls cache_registry.clear_all() instead of hardcoding individual requires.
---
---@module cache_registry
local M = {}

local clear_fns = {}

---Register a cache clear function.
---@param clear_fn function Function that clears module-level caches
function M.register(clear_fn)
    clear_fns[#clear_fns + 1] = clear_fn
end

---Clear all registered caches.
function M.clear_all()
    for _, fn in ipairs(clear_fns) do
        fn()
    end
end

return M
