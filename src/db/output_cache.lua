-- src/core/output_cache.lua
-- Output cache for skipping regeneration when P-IR hasn't changed

local M = {}

local hash_utils = require('infra.hash_utils')
local task_runner = require('infra.process.task_runner')
local Queries = require('db.queries')

function M.new(data, log)
    local self = {
        data = data,
        log = log
    }
    return setmetatable(self, { __index = M })
end

---Check if output is up-to-date for a specification
---@param spec_id string Specification ID
---@param output_path string Output file path
---@return boolean is_current True if output is current and can be skipped
function M:is_output_current(spec_id, output_path)
    -- Check if output file exists
    if not task_runner.file_exists(output_path) then
        if self.log then
            self.log.debug("Output cache miss: file doesn't exist: %s", output_path)
        end
        return false
    end

    -- Get cached P-IR hash for this spec and output path
    local cached = self.data:query_one(Queries.build.get_output_cache, {
        spec = spec_id, path = output_path
    })

    if not cached then
        if self.log then
            self.log.debug("Output cache miss: no cache entry for %s", output_path)
        end
        return false
    end

    -- Compute current P-IR hash
    local current_hash = hash_utils.pir_hash(self.data, spec_id)

    if cached.pir_hash == current_hash then
        if self.log then
            self.log.info("Output cache hit: skipping %s (P-IR unchanged)", output_path)
        end
        return true
    end

    if self.log then
        self.log.debug("Output cache miss: P-IR changed for %s", output_path)
    end
    return false
end

---Update cache after generating output
---@param spec_id string Specification ID
---@param output_path string Output file path
function M:update_cache(spec_id, output_path)
    local pir_hash = hash_utils.pir_hash(self.data, spec_id)

    self.data:execute(Queries.build.update_output_cache, {
        spec = spec_id, path = output_path, hash = pir_hash
    })

    if self.log then
        self.log.debug("Output cache updated for %s (P-IR: %s)", output_path, pir_hash:sub(1, 8))
    end
end

---Invalidate cache for a specification
---@param spec_id string Specification ID
function M:invalidate(spec_id)
    self.data:execute(Queries.build.invalidate_output_cache, { spec = spec_id })
end

---Get cache stats
---@return table stats Cache statistics
function M:get_stats()
    local total = self.data:query_one(Queries.build.get_output_cache_count)

    return {
        entries = total and total.count or 0
    }
end

return M
