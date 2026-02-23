-- Database test utilities
-- Creates in-memory SQLite databases for testing

local M = {}

--- Create a test database with the full SpecCompiler schema
---@return table data DataManager-like object
function M.create_test_db()
    local ok, sqlite = pcall(require, "lsqlite3")
    if not ok then
        error("lsqlite3 is required for tests. Install it or run tests in Docker.")
    end

    local db = sqlite.open_memory()
    if not db then
        error("Failed to create in-memory SQLite database")
    end

    -- Create the core schema
    local schema = [[
        -- Type Definition Tables (7 tables)
        CREATE TABLE IF NOT EXISTS spec_object_types (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL,
            description TEXT,
            is_composite INTEGER DEFAULT 0,
            is_default INTEGER DEFAULT 0,
            header_style_id TEXT,
            body_style_id TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_float_types (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL,
            description TEXT,
            caption_format TEXT,
            counter_group TEXT,
            aliases TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_relation_types (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL,
            source_type_ref TEXT,
            target_type_ref TEXT,
            link_selector TEXT,
            source_attribute TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_view_types (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL,
            description TEXT,
            counter_group TEXT,
            abbrev_type_ref TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_specification_types (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL UNIQUE,
            description TEXT,
            extends TEXT
        );

        CREATE TABLE IF NOT EXISTS datatype_definitions (
            identifier TEXT PRIMARY KEY,
            long_name TEXT NOT NULL,
            type TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS spec_attribute_types (
            identifier TEXT PRIMARY KEY,
            owner_type_ref TEXT NOT NULL,
            long_name TEXT NOT NULL,
            datatype_ref TEXT NOT NULL,
            min_occurs INTEGER DEFAULT 0,
            max_occurs INTEGER DEFAULT 1
        );

        CREATE TABLE IF NOT EXISTS enum_values (
            identifier TEXT PRIMARY KEY,
            datatype_ref TEXT NOT NULL,
            key TEXT NOT NULL,
            sequence INTEGER DEFAULT 0
        );

        -- Instance Tables (6 tables)
        CREATE TABLE IF NOT EXISTS specifications (
            identifier TEXT PRIMARY KEY,
            root_path TEXT NOT NULL,
            long_name TEXT,
            type_ref TEXT,
            pid TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_objects (
            identifier TEXT PRIMARY KEY,
            specification_ref TEXT NOT NULL,
            type_ref TEXT NOT NULL,
            from_file TEXT NOT NULL,
            file_seq INTEGER NOT NULL,
            pid TEXT,
            title_text TEXT,
            label TEXT,
            level INTEGER,
            start_line INTEGER,
            end_line INTEGER,
            parent_ref TEXT,
            ast JSON
        );

        CREATE TABLE IF NOT EXISTS spec_floats (
            identifier TEXT PRIMARY KEY,
            specification_ref TEXT NOT NULL,
            type_ref TEXT NOT NULL,
            from_file TEXT NOT NULL,
            file_seq INTEGER NOT NULL,
            label TEXT NOT NULL,
            number INTEGER,
            caption TEXT,
            pandoc_attributes JSON,
            raw_content TEXT NOT NULL,
            raw_ast JSON,
            resolved_ast JSON,
            content_sha1 TEXT,
            parent_object_ref TEXT,
            anchor TEXT
        );

        CREATE TABLE IF NOT EXISTS spec_relations (
            identifier TEXT PRIMARY KEY,
            specification_ref TEXT NOT NULL,
            source_ref TEXT NOT NULL,
            target_text TEXT,
            target_ref TEXT,
            type_ref TEXT,
            from_file TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS spec_views (
            identifier TEXT PRIMARY KEY,
            specification_ref TEXT NOT NULL,
            view_type_ref TEXT NOT NULL,
            from_file TEXT NOT NULL,
            file_seq INTEGER NOT NULL,
            raw_ast TEXT,
            resolved_ast TEXT,
            resolved_data JSON
        );

        CREATE TABLE IF NOT EXISTS spec_attribute_values (
            identifier TEXT PRIMARY KEY,
            specification_ref TEXT NOT NULL,
            owner_ref TEXT NOT NULL,
            name TEXT NOT NULL,
            raw_value TEXT,
            string_value TEXT,
            int_value INTEGER,
            real_value REAL,
            bool_value INTEGER,
            date_value TEXT,
            datatype TEXT
        );

        -- Type aliases
        CREATE TABLE IF NOT EXISTS implicit_type_aliases (
            alias TEXT PRIMARY KEY,
            object_type_id TEXT NOT NULL
        );

        -- Build graph for incremental builds
        CREATE TABLE IF NOT EXISTS build_graph (
            root_path TEXT NOT NULL,
            node_path TEXT NOT NULL,
            node_sha1 TEXT,
            PRIMARY KEY (root_path, node_path)
        );
        CREATE INDEX IF NOT EXISTS idx_build_graph_root ON build_graph(root_path);

        -- Source files for incremental builds
        CREATE TABLE IF NOT EXISTS source_files (
            path TEXT PRIMARY KEY,
            sha1 TEXT NOT NULL
        );

        -- Output cache for incremental builds
        CREATE TABLE IF NOT EXISTS output_cache (
            spec_id TEXT PRIMARY KEY,
            pir_hash TEXT NOT NULL,
            output_path TEXT,
            generated_at TEXT DEFAULT (datetime('now'))
        );
    ]]

    local result = db:exec(schema)
    if result ~= sqlite.OK then
        error("Failed to create schema: " .. db:errmsg())
    end

    -- Create data wrapper
    local data = {
        db = db,
        sqlite = sqlite
    }

    --- Execute SQL with optional parameters
    ---@param sql string SQL statement
    ---@param params table|nil Named parameters
    function data:execute(sql, params)
        local stmt = self.db:prepare(sql)
        if not stmt then
            error("Failed to prepare: " .. self.db:errmsg() .. "\nSQL: " .. sql)
        end

        if params then
            stmt:bind_names(params)
        end

        local result = stmt:step()
        stmt:finalize()
        return result
    end

    --- Query all rows
    ---@param sql string SQL query
    ---@param params table|nil Named parameters
    ---@return table rows Array of row tables
    function data:query_all(sql, params)
        local stmt = self.db:prepare(sql)
        if not stmt then
            error("Failed to prepare: " .. self.db:errmsg() .. "\nSQL: " .. sql)
        end

        if params then
            stmt:bind_names(params)
        end

        local results = {}
        while stmt:step() == self.sqlite.ROW do
            table.insert(results, stmt:get_named_values())
        end
        stmt:finalize()
        return results
    end

    --- Query single row
    ---@param sql string SQL query
    ---@param params table|nil Named parameters
    ---@return table|nil row First row or nil
    function data:query_one(sql, params)
        local results = self:query_all(sql, params)
        return results and results[1] or nil
    end

    --- Close the database
    function data:close()
        if self.db then
            self.db:close()
            self.db = nil
        end
    end

    return data
end

--- Seed type aliases into the database
---@param data table DataManager-like object
---@param aliases table Map of alias -> type_id
function M.seed_type_aliases(data, aliases)
    for alias, type_id in pairs(aliases) do
        data:execute([[
            INSERT OR REPLACE INTO implicit_type_aliases (alias, object_type_id)
            VALUES (:alias, :type_id)
        ]], { alias = alias, type_id = type_id })
    end
end

--- Seed default object types
---@param data table DataManager-like object
function M.seed_default_types(data)
    local types = {
        { id = "SPEC", long_name = "Specification", is_composite = 1, is_default = 0 },
        { id = "SRS", long_name = "Software Requirements Specification", is_composite = 1, is_default = 0 },
        { id = "SDD", long_name = "Software Design Description", is_composite = 1, is_default = 0 },
        { id = "SVC", long_name = "Software Verification Cases", is_composite = 1, is_default = 0 },
        { id = "SECTION", long_name = "Section", is_composite = 0, is_default = 1 },  -- Default type for headers without type prefix
        { id = "HLR", long_name = "High-Level Requirement", is_composite = 0, is_default = 0 },
        { id = "LLR", long_name = "Low-Level Requirement", is_composite = 0, is_default = 0 },
        { id = "FD", long_name = "Functional Description", is_composite = 0, is_default = 0 },
        { id = "VC", long_name = "Verification Case", is_composite = 0, is_default = 0 },
        { id = "DD", long_name = "Data Dictionary", is_composite = 0, is_default = 0 }
    }

    for _, t in ipairs(types) do
        data:execute([[
            INSERT OR REPLACE INTO spec_object_types (identifier, long_name, is_composite, is_default)
            VALUES (:id, :long_name, :is_composite, :is_default)
        ]], t)
    end

    -- Also seed specification types (level-1 header types)
    local spec_types = {
        { id = "SPEC", long_name = "Specification" },
        { id = "SRS", long_name = "Software Requirements Specification" },
        { id = "SDD", long_name = "Software Design Description" },
        { id = "SVC", long_name = "Software Verification Cases" }
    }
    for _, t in ipairs(spec_types) do
        data:execute([[
            INSERT OR REPLACE INTO spec_specification_types (identifier, long_name)
            VALUES (:id, :long_name)
        ]], t)
    end
end

--- Seed default float types
---@param data table DataManager-like object
function M.seed_float_types(data)
    -- Note: First alias in list is used as type prefix for anchors
    local types = {
        { id = "CSV", long_name = "CSV Table", caption_format = "Table", counter_group = "TABLE", aliases = ",csv," },
        { id = "TSV", long_name = "TSV Table", caption_format = "Table", counter_group = "TABLE", aliases = ",tsv," },
        { id = "LIST_TABLE", long_name = "List Table", caption_format = "Table", counter_group = "TABLE", aliases = ",list-table,listtable," },
        { id = "TABLE", long_name = "Table", caption_format = "Table", counter_group = "TABLE", aliases = ",tbl,table," },
        { id = "FIG", long_name = "Figure", caption_format = "Figure", counter_group = "FIGURE", aliases = ",fig,figure," },
        { id = "FIGURE", long_name = "Figure", caption_format = "Figure", counter_group = "FIGURE", aliases = ",fig,figure," },
        { id = "PUML", long_name = "PlantUML Diagram", caption_format = "Figure", counter_group = "FIGURE", aliases = ",puml,plantuml," },
        { id = "LISTING", long_name = "Listing", caption_format = "Listing", counter_group = "LISTING", aliases = ",lis,listing," },
        { id = "SRC", long_name = "Source Code", caption_format = "Listing", counter_group = "LISTING", aliases = ",src,source," },
        { id = "MATH", long_name = "Math Equation", caption_format = "Equation", counter_group = "EQUATION", aliases = ",mat,math,equation," },
        { id = "CHART", long_name = "Chart", caption_format = "Figure", counter_group = "FIGURE", aliases = ",chart,echarts," },
        { id = "CODE", long_name = "Code Block", caption_format = "Code", counter_group = "LISTING", aliases = ",cod,code," },
        { id = "EQUATION", long_name = "Equation", caption_format = "Equation", counter_group = "EQUATION", aliases = ",equ,equation," }
    }

    for _, t in ipairs(types) do
        data:execute([[
            INSERT OR REPLACE INTO spec_float_types (identifier, long_name, caption_format, counter_group, aliases)
            VALUES (:id, :long_name, :caption_format, :counter_group, :aliases)
        ]], t)
    end
end

--- Count rows in a table with optional WHERE clause
---@param data table DataManager-like object
---@param table_name string Table name
---@param where_clause string|nil Optional WHERE clause
---@param params table|nil Optional parameters
---@return number count
function M.count_rows(data, table_name, where_clause, params)
    local sql = string.format("SELECT COUNT(*) as cnt FROM %s", table_name)
    if where_clause then
        sql = sql .. " WHERE " .. where_clause
    end
    local rows = data:query_all(sql, params or {})
    return rows[1] and rows[1].cnt or 0
end

return M
