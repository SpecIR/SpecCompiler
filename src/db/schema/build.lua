---Build infrastructure schema tables for SpecCompiler.
-- Defines build_graph, source_files, and output_cache.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- BUILD INFRASTRUCTURE TABLES
--
-- These tables enable incremental builds by tracking:
-- 1. File dependencies (which files include which other files)
-- 2. File content hashes (to detect when files change)
-- 3. Output artifacts (to skip regenerating unchanged outputs)
--
-- Key insight: A document needs rebuilding if ANY included file changes.
-- The build_graph tracks this include tree for fast invalidation.
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 14. BUILD GRAPH
-- Tracks include/dependency relationships between files.
-- When a node file changes, all root files that include it are invalidated.
-- Populated by include_handler during INITIALIZE phase.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS build_graph (
  -- Root document path (the specification being built)
  -- This is the file that will be rebuilt if any node changes
  root_path TEXT NOT NULL,

  -- Included/dependency file path
  -- This file is included (directly or transitively) by root_path
  -- Can be the same as root_path (self-reference for the root itself)
  node_path TEXT NOT NULL,

  -- SHA1 hash of node file content at last build
  -- Used to detect if this node has changed since last build
  -- NULL means the node hasn't been hashed yet
  node_sha1 TEXT,

  -- Composite key: each root can include each node at most once
  PRIMARY KEY (root_path, node_path)
);

-- Reverse lookup: "which roots include this changed node?"
-- Used for incremental builds: when a file changes, find all specs to rebuild
-- Note: root_path lookups are already covered by the composite PK left-prefix
CREATE INDEX IF NOT EXISTS idx_build_graph_node ON build_graph(node_path);

--------------------------------------------------------------------------------
-- 15. SOURCE FILES
-- Simple cache of file paths to their content hashes.
-- Used for fast "has this file changed?" checks.
-- Updated whenever a file is processed.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS source_files (
  -- Absolute or project-relative file path
  path TEXT PRIMARY KEY,

  -- SHA1 hash of file content
  -- Compared against current file hash to detect changes
  sha1 TEXT NOT NULL
);

--------------------------------------------------------------------------------
-- 16. OUTPUT CACHE
-- Tracks generated output files and their source state.
-- Enables skipping Pandoc rendering when inputs haven't changed.
-- Key optimization: Pandoc conversion is expensive, caching saves minutes.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS output_cache (
  -- Specification identifier (FK to specifications.identifier)
  -- Identifies which document produced this output
  spec_id TEXT NOT NULL,

  -- Output file path (e.g., "output/SRS-001.docx", "output/SRS-001.html")
  -- Each spec can have multiple outputs (different formats)
  output_path TEXT NOT NULL,

  -- Hash of Pandoc Intermediate Representation (PIR)
  -- PIR = assembled AST + metadata before Pandoc rendering
  -- If PIR hash matches, output doesn't need regenerating
  pir_hash TEXT NOT NULL,

  -- Timestamp when this output was generated
  -- Used for cache age reporting and debugging
  generated_at TEXT DEFAULT (datetime('now')),

  -- Composite key: one cache entry per spec + output format
  PRIMARY KEY (spec_id, output_path)
);
]]

return M
