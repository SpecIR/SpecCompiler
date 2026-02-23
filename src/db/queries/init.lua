---Query module initialization for SpecCompiler.
-- Exports all domain-specific query modules.
--
-- CONVENTION:
--   All parameterized SQL queries live in this module tree (db.queries.*).
--   Pipeline handlers reference them via `Queries.<domain>.<name>`.
--
--   Naming:  M.{verb}_{noun}[_{qualifier}]   e.g. insert_object, objects_by_spec_type
--   Builders: M.build_{purpose}(args) → SQL string  (for dynamic IN clauses, CASE updates)
--
--   Justified inline SQL exceptions are marked with `-- INLINE SQL: <reason>` in:
--     • verify_handler.lua   — runtime table name from model proof definitions
--     • fts_indexer.lua      — DDL / PRAGMA (schema ops, not data queries)
--     • eav_pivot.lua        — dynamically generated CREATE VIEW from type metadata

local M = {}

-- Load domain-specific query modules
M.types = require('db.queries.types')
M.content = require('db.queries.content')
M.search = require('db.queries.search')
M.build = require('db.queries.build')
M.resolution = require('db.queries.resolution')
M.pid = require('db.queries.pid')
M.assembly = require('db.queries.assembly')
M.materialization = require('db.queries.materialization')

return M
