-- src/db/output_cache.lua
-- Output cache for skipping Pandoc rendering when its input hasn't changed.
--
-- The cache key is the hash of the exact serialized document fed to the
-- Pandoc CLI (assembled from the DB, views rendered, format filter applied).
-- Anything that changes the rendered output — own content, cross-document
-- view data, template filters — changes this hash by construction, so no
-- dependency modeling is needed.

local M = {}

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
---@param dependencies string[]|nil Extra files that affect this output
---@param input_hash string Hash of the serialized document to be rendered
---@return boolean is_current True if output is current and can be skipped
function M:is_output_current(spec_id, output_path, dependencies, input_hash)
    -- Check if output file exists
    if not task_runner.file_exists(output_path) then
        if self.log then
            self.log.debug("Output cache miss: file doesn't exist: %s", output_path)
        end
        return false
    end

    local output_mtime = task_runner.file_mtime(output_path)
    for _, dep_path in ipairs(dependencies or {}) do
        local dep_mtime = task_runner.file_mtime(dep_path)
        if dep_mtime and output_mtime and dep_mtime > output_mtime then
            if self.log then
                self.log.debug("Output cache miss: dependency changed for %s: %s", output_path, dep_path)
            end
            return false
        end
    end

    local cached = self.data:query_one(Queries.build.get_output_cache, {
        spec = spec_id, path = output_path
    })

    if not cached then
        if self.log then
            self.log.debug("Output cache miss: no cache entry for %s", output_path)
        end
        return false
    end

    if cached.pir_hash == input_hash then
        if self.log then
            self.log.info("Output cache hit: skipping %s (render input unchanged)", output_path)
        end
        return true
    end

    if self.log then
        self.log.debug("Output cache miss: render input changed for %s", output_path)
    end
    return false
end

---Update cache after generating output
---@param spec_id string Specification ID
---@param output_path string Output file path
---@param input_hash string Hash of the serialized document that was rendered
function M:update_cache(spec_id, output_path, input_hash)
    self.data:execute(Queries.build.update_output_cache, {
        spec = spec_id, path = output_path, hash = input_hash
    })

    if self.log then
        self.log.debug("Output cache updated for %s (input: %s)", output_path, input_hash:sub(1, 8))
    end
end

return M
