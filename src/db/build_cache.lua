-- src/core/build_cache.lua
local Queries = require("db.queries")

local M = {}

function M.new(data)
    local self = {
        data = data
    }
    return setmetatable(self, { __index = M })
end

---Check if a document needs rebuilding based on its hash
---@param path string Document path
---@param current_hash string Current SHA1 of document
---@return boolean dirty True if document needs rebuilding
function M:is_document_dirty(path, current_hash)
    local cached = self.data:query_one(Queries.build.get_source_file_hash, { path = path })

    if not cached then
        return true -- No cache = dirty
    end

    return cached.sha1 ~= current_hash
end

---Update the cached hash for a document
---@param path string Document path
---@param hash string New SHA1 hash
function M:update_document_hash(path, hash)
    self.data:execute(Queries.build.update_source_file_hash, { path = path, hash = hash })
end

---Check if document or any of its includes need rebuilding
---@param root_path string Root document path
---@param root_hash string Current SHA1 of root document
---@param include_hashes table Map of include_path -> current_hash
---@return boolean dirty True if any file in tree changed
function M:is_document_dirty_with_includes(root_path, root_hash, include_hashes)
    -- Check root document
    if self:is_document_dirty(root_path, root_hash) then
        return true
    end

    -- Check includes from build_graph
    local includes = self.data:query_all(Queries.build.get_includes_for_root, { root = root_path })

    for _, inc in ipairs(includes or {}) do
        local current_hash = include_hashes[inc.node_path]
        if not current_hash then
            -- Missing include must invalidate cache so parse can fail fast with
            -- a clear include-not-found error instead of serving stale output.
            return true
        end
        if current_hash and current_hash ~= inc.node_sha1 then
            return true
        end
    end

    return false
end

---Update build graph for a document
---@param root_path string Root document path
---@param includes table Array of {path, hash} for includes
function M:update_build_graph(root_path, includes)
    -- Clear old entries
    self.data:execute(Queries.build.clear_build_graph, { root = root_path })

    -- Insert new entries
    for _, inc in ipairs(includes or {}) do
        self.data:execute(Queries.build.insert_build_graph_node, {
            root = root_path, node = inc.path, hash = inc.hash
        })
    end
end

return M
