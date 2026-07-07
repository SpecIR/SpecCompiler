---Build infrastructure schema tables for SpecCompiler.
-- Defines build_graph and output_cache.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- BUILD INFRASTRUCTURE TABLES
--
-- These tables enable incremental builds by tracking:
-- 1. Source file hashes per document (root + includes) to skip re-parsing
-- 2. Output artifacts (to skip regenerating unchanged outputs)
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 14. BUILD GRAPH
-- The file set of each document build: the root document itself plus every
-- file it includes (directly or transitively), each with the SHA1 it had at
-- the last successful build. A document is dirty when any node's current
-- hash differs, a node file is missing, or its root node is absent.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS build_graph (
  -- Root document path (the specification being built)
  root_path TEXT NOT NULL,

  -- A file this build read: the root itself, or an include
  node_path TEXT NOT NULL,

  -- SHA1 hash of node file content at last successful build
  node_sha1 TEXT,

  -- Composite key: each root records each node at most once
  PRIMARY KEY (root_path, node_path)
);

-- Reverse lookup: "which roots include this changed node?"
-- Note: root_path lookups are already covered by the composite PK left-prefix
CREATE INDEX IF NOT EXISTS idx_build_graph_node ON build_graph(node_path);

--------------------------------------------------------------------------------
-- 15. OUTPUT CACHE
-- Tracks generated output files and the hash of the serialized document that
-- produced them (the exact Pandoc input, after assembly, view rendering and
-- format filters). If that hash matches, the Pandoc render can be skipped.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS output_cache (
  -- Specification identifier (FK to specifications.identifier)
  spec_id TEXT NOT NULL,

  -- Output file path (e.g., "output/SRS-001.docx", "output/SRS-001.html")
  -- Each spec can have multiple outputs (different formats)
  output_path TEXT NOT NULL,

  -- SHA1 of the serialized (filtered) document fed to Pandoc.
  -- ponytail: legacy column name kept so existing cache DBs keep working;
  -- it no longer stores a "P-IR" dependency-model hash.
  pir_hash TEXT NOT NULL,

  -- Timestamp when this output was generated
  generated_at TEXT DEFAULT (datetime('now')),

  -- Composite key: one cache entry per spec + output format
  PRIMARY KEY (spec_id, output_path)
);
]]

return M
