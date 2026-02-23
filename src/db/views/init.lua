---Views module initialization for SpecCompiler.
-- Exports and initializes all view modules.
--
-- View categories:
-- - eav_pivot: Per-object-type views that pivot EAV attributes into columns
-- - public_api: Stable BI-friendly views for customer dashboards
-- - resolution: Internal views for handler resolution logic

local M = {}

-- Load view modules
M.eav_pivot = require('db.views.eav_pivot')
M.public_api = require('db.views.public_api')
M.resolution = require('db.views.resolution')

---Initialize all views.
---Should be called after schema and type data are loaded.
---@param db table DataManager (db.db = DbHandler)
function M.initialize(db)
    -- Resolution and public_api use multi-statement DDL requiring exec_sql.
    -- DataManager:execute only prepares the first SQL statement (lsqlite3 limitation).
    -- Pass DbHandler directly so they can use exec_sql (sqlite3_exec for all statements).
    local handler = db.db

    -- 1. Resolution views first (used by other views and handlers)
    M.resolution.initialize(handler)

    -- 2. Public API views (static SQL)
    M.public_api.initialize(handler)

    -- 3. EAV pivot views last (dynamically generated from type definitions)
    -- EAV pivot needs DataManager for query_all + single-statement execute per type
    M.eav_pivot.initialize(db)
end

return M
