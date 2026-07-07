-- src/db/build_cache.lua
-- Incremental parse cache: one build_graph table stores the root document
-- AND its includes as nodes (the root is its own node), each with the SHA1
-- it had at the last successful build. A document is dirty when any node's
-- current hash differs, a node file is missing, or no root node is recorded
-- (first build, failed previous build, or a pre-consolidation cache DB).
local Queries = require("db.queries")
local hash_utils = require("infra.hash_utils")

local M = {}

function M.new(data)
    local self = {
        data = data
    }
    return setmetatable(self, { __index = M })
end

---Check whether a document or any file in its include tree changed.
---@param root_path string Root document path
---@param current_root_hash string Current SHA1 of the root document
---@return boolean dirty True if the document needs rebuilding
function M:is_document_dirty(root_path, current_root_hash)
    local nodes = self.data:query_all(Queries.build.get_nodes_for_root, { root = root_path })

    local root_seen = false
    for _, node in ipairs(nodes or {}) do
        local current
        if node.node_path == root_path then
            root_seen = true
            current = current_root_hash
        else
            -- Missing include hashes to nil → dirty, so parse fails fast with
            -- a clear include-not-found error instead of serving stale output.
            current = hash_utils.sha1_file(node.node_path)
        end
        if not current or current ~= node.node_sha1 then
            return true
        end
    end

    return not root_seen
end

---Record the file set (root + includes) and their hashes for a document.
---@param root_path string Root document path
---@param root_hash string SHA1 of the root document as built
---@param includes table Array of {path, hash} for includes
function M:update_build_graph(root_path, root_hash, includes)
    self.data:execute(Queries.build.clear_build_graph, { root = root_path })
    self.data:execute(Queries.build.insert_build_graph_node, {
        root = root_path, node = root_path, hash = root_hash
    })
    for _, inc in ipairs(includes or {}) do
        self.data:execute(Queries.build.insert_build_graph_node, {
            root = root_path, node = inc.path, hash = inc.hash
        })
    end
end

return M
