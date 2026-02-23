---Schema initialization module for SpecCompiler.
-- Combines all domain-specific schema modules and exports combined SQL.
-- Also provides views initialization after type data is loaded.
--
-- Clean break: no migration logic. Databases are transient and rebuilt
-- from source markdown. Old databases should be deleted before running
-- with the new schema.

local M = {}

-- Load domain-specific schema modules
M.types = require('db.schema.types')
M.content = require('db.schema.content')
M.build = require('db.schema.build')
M.search = require('db.schema.search')

-- Combined SQL for initialization (order matters for foreign keys)
-- Types must come first (referenced by content tables)
-- Content second (references types)
-- Build, search can come in any order (no cross-dependencies)
M.SQL = M.types.SQL .. M.content.SQL .. M.build.SQL .. M.search.SQL

---Initialize views after type data is loaded.
---Views depend on type definitions (spec_attribute_types, spec_object_types).
---Call this AFTER loading model type data.
---@param db table Database handler with :execute and :query_all methods
function M.initialize_views(db)
    local views = require('db.views')
    views.initialize(db)
end

return M
