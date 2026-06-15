---Views module initialization for SpecCompiler.
-- Exports and initializes all view modules.
--
-- View categories:
-- - eav_pivot: Per-object-type views that pivot EAV attributes into columns
-- - public_api: Stable BI-friendly views for customer dashboards

local M = {}

-- Load view modules
M.eav_pivot = require('db.views.eav_pivot')
M.public_api = require('db.views.public_api')

---Initialize all views.
---Should be called after schema and type data are loaded.
---@param db table DataManager (db.db = DbHandler)
function M.initialize(db)
    -- public_api uses multi-statement DDL requiring exec_sql.
    -- DataManager:execute only prepares the first SQL statement (lsqlite3 limitation).
    -- Pass DbHandler directly so they can use exec_sql (sqlite3_exec for all statements).
    local handler = db.db

    -- 1. Public API views (static SQL)
    M.public_api.initialize(handler)

    -- 2. EAV pivot views last (dynamically generated from type definitions)
    -- EAV pivot needs DataManager for query_all + single-statement execute per type
    M.eav_pivot.initialize(db)
end

return M
