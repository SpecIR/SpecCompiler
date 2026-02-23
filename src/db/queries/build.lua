---Build infrastructure queries for SpecCompiler.
-- INSERT/DELETE/SELECT operations for build_graph, source_files, output_cache.

local M = {}

-- ============================================================================
-- Source Files (change detection)
-- ============================================================================

M.get_source_file_hash = [[
    SELECT sha1 FROM source_files WHERE path = :path
]]

M.update_source_file_hash = [[
    INSERT OR REPLACE INTO source_files (path, sha1)
    VALUES (:path, :hash)
]]

-- ============================================================================
-- Build Graph (include dependencies)
-- ============================================================================

M.get_includes_for_root = [[
    SELECT node_path, node_sha1 FROM build_graph WHERE root_path = :root
]]

M.clear_build_graph = [[
    DELETE FROM build_graph WHERE root_path = :root
]]

M.insert_build_graph_node = [[
    INSERT INTO build_graph (root_path, node_path, node_sha1)
    VALUES (:root, :node, :hash)
]]

-- Upsert build graph node (for include handler, may re-include same path)
M.upsert_build_graph_node = [[
    INSERT OR REPLACE INTO build_graph (root_path, node_path, node_sha1)
    VALUES (:root, :node, :sha1)
]]

-- ============================================================================
-- Output Cache (P-IR hash)
-- ============================================================================

M.get_output_cache = [[
    SELECT pir_hash FROM output_cache
    WHERE spec_id = :spec AND output_path = :path
]]

M.update_output_cache = [[
    INSERT OR REPLACE INTO output_cache (spec_id, output_path, pir_hash, generated_at)
    VALUES (:spec, :path, :hash, datetime('now'))
]]

M.invalidate_output_cache = [[
    DELETE FROM output_cache WHERE spec_id = :spec
]]

M.get_output_cache_count = [[
    SELECT COUNT(*) as count FROM output_cache
]]

return M
