---Simplified IR Data Manager for SpecCompiler.

local Schema = require('db.schema')

local M = {}

function M.new(db_handler, log)
    local self = setmetatable({}, { __index = M })
    self.db = db_handler
    self.log = log
    self._resolvers = {}

    -- Initialize schema from domain-specific modules
    self.db:exec_sql(Schema.SQL)

    return self
end

---Register a resolver function for a base relation type.
---Called by type_loader when loading base relation types (e.g. PID_REF, LABEL_REF).
---Resolution is type-driven: the type's extends chain determines which resolver to use.
---@param type_id string Base relation type identifier ("PID_REF", "LABEL_REF", etc.)
---@param fn function Resolver function(data, spec_id, target_text, source_object_id)
function M:register_resolver(type_id, fn)
    self._resolvers[type_id] = fn
end

---Get the resolver function for a base relation type.
---@param type_id string|nil Base relation type identifier
---@return function|nil resolver
function M:get_resolver(type_id)
    return type_id and self._resolvers[type_id] or nil
end

function M:query_all(sql, params)
    return self.db:query_all(sql, params or {})
end

function M:query_one(sql, params)
    local results = self.db:query_all(sql, params or {})
    return results and results[1] or nil
end

function M:execute(sql, params)
    local stmt = self.db:prepare_statement(sql, "execute")
    local res = self.db:execute_prepared(stmt, params)
    stmt:finalize()
    return res
end

---Begin a transaction for batch operations.
---Dramatically improves performance for multiple INSERTs (100x or more).
---@return boolean success
function M:begin_transaction()
    return self.db:begin_transaction()
end

---Commit the current transaction.
---@return boolean success
function M:commit()
    return self.db:commit()
end

---Rollback the current transaction on error.
---@return boolean success
function M:rollback()
    return self.db:rollback()
end

---Get the rowid of the last INSERT.
---Used with INTEGER PRIMARY KEY tables to retrieve auto-assigned ids.
---@return integer rowid
function M:last_insert_rowid()
    return self.db:last_insert_rowid()
end

return M
