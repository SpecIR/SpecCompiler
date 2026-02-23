---Full-text search schema tables for SpecCompiler.
-- Defines FTS5 virtual tables: fts_objects, fts_attributes, fts_floats.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- FULL-TEXT SEARCH TABLES (FTS5 Virtual Tables)
--
-- SQLite FTS5 enables fast text search across specification content.
-- Denormalized: content is duplicated from main tables for search performance.
-- Populated by fts_indexer during EMIT phase.
--
-- FTS5 features used:
-- - porter: English stemming (search "run" matches "running")
-- - unicode61: Unicode-aware tokenization
-- - UNINDEXED: Columns stored but not searchable (for JOINs back to main tables)
--
-- Query examples:
-- - Simple: SELECT * FROM fts_objects WHERE fts_objects MATCH 'authentication'
-- - Phrase: SELECT * FROM fts_objects WHERE fts_objects MATCH '"user login"'
-- - Boolean: SELECT * FROM fts_objects WHERE fts_objects MATCH 'user AND NOT admin'
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- 17. FTS INDEX FOR SPEC OBJECTS
-- Full-text search on requirements, tests, features, etc.
-- Enables searching across all content in a specification.
--------------------------------------------------------------------------------
CREATE VIRTUAL TABLE IF NOT EXISTS fts_objects USING fts5(
  -- Object identifier (FK to spec_objects.identifier)
  -- UNINDEXED = stored but not searchable, used for JOIN back to main table
  identifier UNINDEXED,

  -- Object type (HLR, FD, VC, TP, etc.) for filtering
  -- UNINDEXED = enables "WHERE object_type = 'HLR'" without indexing type text
  object_type UNINDEXED,

  -- Specification ID for scoping searches to one document
  spec_id UNINDEXED,

  -- Object title - INDEXED for search
  -- High relevance: matches in title rank higher
  title,

  -- Object body content (plain text, markdown stripped) - INDEXED
  -- Main searchable content
  content,

  -- Original markdown source - INDEXED
  -- Useful for code searches, literal syntax matches
  raw_source,

  -- Tokenization: porter stemmer + unicode support
  tokenize='porter unicode61'
);

--------------------------------------------------------------------------------
-- 18. FTS INDEX FOR ATTRIBUTES
-- Faceted search by attribute name and value.
-- Enables queries like "find all objects where status contains 'approved'"
--------------------------------------------------------------------------------
CREATE VIRTUAL TABLE IF NOT EXISTS fts_attributes USING fts5(
  -- Owner object identifier (FK to spec_objects.identifier or spec_floats.identifier)
  owner_ref UNINDEXED,

  -- Specification ID for scoping searches to one document
  -- UNINDEXED so it can be used for filtering without affecting ranking/tokenization.
  spec_id UNINDEXED,

  -- Attribute name (status, priority, rationale, etc.)
  -- UNINDEXED = enables filtering "WHERE attr_name = 'status'"
  attr_name UNINDEXED,

  -- Attribute datatype (STRING, INTEGER, ENUM, etc.)
  attr_type UNINDEXED,

  -- Attribute value as text - INDEXED for search
  -- All types coerced to string for full-text search
  attr_value,

  tokenize='porter unicode61'
);

--------------------------------------------------------------------------------
-- 19. FTS INDEX FOR FLOATS
-- Search across figures, tables, diagrams, PlantUML, etc.
-- Enables finding diagrams by caption or source content.
--------------------------------------------------------------------------------
CREATE VIRTUAL TABLE IF NOT EXISTS fts_floats USING fts5(
  -- Float identifier (FK to spec_floats.identifier)
  identifier UNINDEXED,

  -- Float type (FIGURE, TABLE, CHART, PLANTUML, etc.)
  float_type UNINDEXED,

  -- Specification ID for scoping searches to one document
  spec_id UNINDEXED,

  -- Parent object identifier (for scoped searches)
  parent_ref UNINDEXED,

  -- Caption text - INDEXED
  -- Primary search target for floats
  caption,

  -- Raw source content (PlantUML code, table data, etc.) - INDEXED
  -- Enables searching diagram source code
  raw_source,

  tokenize='porter unicode61'
);
]]

return M
