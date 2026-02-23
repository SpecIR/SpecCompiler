---Simplified Database Handler for SpecCompiler.

local M = {}

local sqlite = require("lsqlite3")

function M.new(config)
    local self = setmetatable({}, { __index = M })
    self.log = config.log
    self.sqlite = sqlite
    self.db = sqlite.open(config.db_file)
    -- Use DELETE journal mode to avoid WAL/SHM file issues on WSL2.
    -- SpecCompiler is single-process, so WAL's concurrent-read benefit is unused.
    self.db:exec("PRAGMA journal_mode=DELETE;")
    return self
end

function M:execute(sql, params)
    local stmt, err = self.db:prepare(sql)
    if not stmt then
        local errmsg = self.db:errmsg() or "unknown error"
        error("Failed to prepare SQL: " .. tostring(err) .. " (" .. errmsg .. ")\nSQL: " .. sql)
    end
    if params then
        stmt:bind_names(params)
    end
    local res = stmt:step()
    stmt:finalize()
    return res == self.sqlite.DONE
end

function M:query_all(sql, params)
    local results = {}
    local stmt, err = self.db:prepare(sql)
    if not stmt then
        local errmsg = self.db:errmsg() or "unknown error"
        error("Failed to prepare SQL: " .. tostring(err) .. " (" .. errmsg .. ")\nSQL: " .. sql)
    end
    if params then
        stmt:bind_names(params)
    end
    while stmt:step() == self.sqlite.ROW do
        table.insert(results, stmt:get_named_values())
    end
    stmt:finalize()
    return results
end

function M:exec_sql(sql)
    local result = self.db:exec(sql)
    if result ~= self.sqlite.OK then
        local errmsg = self.db:errmsg() or "unknown error"
        error("Failed to execute SQL: " .. tostring(result) .. " (" .. errmsg .. ")")
    end
    return result
end

function M:prepare_statement(sql)
    local stmt, err = self.db:prepare(sql)
    if not stmt then
        local errmsg = self.db:errmsg() or "unknown error"
        error("Failed to prepare SQL: " .. tostring(err) .. " (" .. errmsg .. ")\nSQL: " .. sql)
    end
    return stmt
end

function M:execute_prepared(stmt, params)
    if not stmt then
        error("Attempted to execute nil statement")
    end
    if params then
        stmt:bind_names(params)
    end
    return stmt:step()
end

---Begin a transaction for batch operations.
---Dramatically improves performance for multiple INSERTs.
---@return boolean success
function M:begin_transaction()
    return self.db:exec("BEGIN TRANSACTION") == self.sqlite.OK
end

---Commit the current transaction.
---@return boolean success
function M:commit()
    return self.db:exec("COMMIT") == self.sqlite.OK
end

---Rollback the current transaction on error.
---@return boolean success
function M:rollback()
    return self.db:exec("ROLLBACK") == self.sqlite.OK
end

---Get the rowid of the last INSERT.
---@return integer rowid
function M:last_insert_rowid()
    return self.db:last_insert_rowid()
end

---Close the database connection.
---Should be called when done with the database to release file handles.
function M:close()
    if self.db then
        self.db:close()
        self.db = nil
    end
end

return M
