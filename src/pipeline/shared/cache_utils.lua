-- src/pipeline/shared/cache_utils.lua
-- Minimal cache utilities for pipeline module-level caches.

local M = {}

---Create a key-value cache backed by a loader function.
---The loader is called on cache miss with (key, ...) and its result is stored.
---@param loader function(key: string, ...): any
---@return table cache Object with :get(key, ...) and :clear()
function M.create_map(loader)
    local store = {}
    return {
        get = function(self, key, ...)
            if store[key] ~= nil then
                return store[key]
            end
            local value = loader(key, ...)
            store[key] = value
            return value
        end,
        clear = function(self)
            store = {}
        end,
    }
end

---Create a singleton cache that computes its value once.
---The loader is called on first access with any forwarded arguments.
---@param loader function(...): any
---@return table cache Object with :get(...) and :clear()
function M.create_once(loader)
    local value = nil
    local loaded = false
    return {
        get = function(self, ...)
            if loaded then
                return value
            end
            value = loader(...)
            loaded = true
            return value
        end,
        clear = function(self)
            value = nil
            loaded = false
        end,
    }
end

return M
