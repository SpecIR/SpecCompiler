---Build infrastructure queries for SpecCompiler.
-- INSERT/DELETE/SELECT operations for build_graph and output_cache.

local M = {}

-- ============================================================================
-- Build Graph (root + include dependencies; the root is its own node)
-- ============================================================================

M.get_nodes_for_root = [[
    SELECT node_path, node_sha1 FROM build_graph WHERE root_path = :root
]]

M.clear_build_graph = [[
    DELETE FROM build_graph WHERE root_path = :root
]]

M.insert_build_graph_node = [[
    INSERT OR REPLACE INTO build_graph (root_path, node_path, node_sha1)
    VALUES (:root, :node, :hash)
]]

-- ============================================================================
-- Output Cache (hash of the serialized document fed to Pandoc)
-- ============================================================================

M.get_output_cache = [[
    SELECT pir_hash FROM output_cache
    WHERE spec_id = :spec AND output_path = :path
]]

M.update_output_cache = [[
    INSERT OR REPLACE INTO output_cache (spec_id, output_path, pir_hash, generated_at)
    VALUES (:spec, :path, :hash, datetime('now'))
]]

return M
