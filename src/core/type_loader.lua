---Type Loader for SpecCompiler.
---Responsible for loading type modules and populating IR type tables.
---
---Supports loading type modules from:
---  - Single files: models/{model}/types/floats/figure.lua
---  - Subdirectories: models/{model}/types/floats/figure/init.lua
---
---@module type_loader
local DT = require("core.datatypes")
local M = {}

local uv = require("luv")
local Queries = require("db.queries")

local KNOWN_CATEGORIES = { "objects", "floats", "views", "relations", "specifications" }


-- Filesystem functions using luv
local function create_fs_adapter(uv_lib)
    local adapter = {}

    adapter.cwd = function() return uv_lib.cwd() end
    adapter.stat = function(path) return uv_lib.fs_stat(path) end
    adapter.scandir = function(path)
        local req, err = uv_lib.fs_scandir(path)
        if not req then return nil, err end
        local entries = {}
        while true do
            local name, entry_type = uv_lib.fs_scandir_next(req)
            if not name then break end
            table.insert(entries, { name = name, type = entry_type })
        end
        return entries
    end

    return adapter
end

local fs = create_fs_adapter(uv)

---Register a float type into spec_float_types.
---@param data DataManager
---@param schema table Float type schema
local function register_float_type(data, schema)
    if not schema or not schema.id then return end

    -- Serialize aliases to comma-separated string for SQL LIKE matching
    local aliases_str = nil
    if schema.aliases and #schema.aliases > 0 then
        aliases_str = "," .. table.concat(schema.aliases, ",") .. ","
    end

    data:execute(Queries.types.insert_float_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        caption_format = schema.caption_format or schema.id,
        counter_group = schema.counter_group or schema.id,
        aliases = aliases_str,
        needs_external_render = schema.needs_external_render and 1 or 0
    })
end

---Register a relation type into spec_relation_types.
---@param data DataManager
---@param schema table Relation type schema
local function register_relation_type(data, schema)
    if not schema or not schema.id then return end

    data:execute(Queries.types.insert_relation_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        link_selector = schema.link_selector,
        source_attribute = schema.source_attribute,
        source_type_ref = schema.source_type_ref,
        target_type_ref = schema.target_type_ref
    })
end

---Register an object type into spec_object_types.
---@param data DataManager
---@param schema table Object type schema
local function register_object_type(data, schema)
    if not schema or not schema.id then return end

    -- Serialize aliases to comma-separated string for SQL LIKE matching
    local aliases_str = nil
    if schema.aliases and #schema.aliases > 0 then
        aliases_str = "," .. table.concat(schema.aliases, ",") .. ","
    end

    data:execute(Queries.types.insert_object_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        is_composite = schema.is_composite and 1 or 0,
        is_required = schema.is_required and 1 or 0,
        is_default = schema.is_default and 1 or 0,
        pid_prefix = schema.pid_prefix,  -- Default PID prefix for auto-generation
        pid_format = schema.pid_format,  -- Printf format (e.g., "%s-%03d")
        aliases = aliases_str
    })

    -- Register implicit type aliases (title -> type mapping)
    if schema.implicit_aliases then
        for _, alias in ipairs(schema.implicit_aliases) do
            data:execute(Queries.types.insert_implicit_alias, {
                alias = alias,
                type_id = schema.id
            })
        end
    end
end

---Register a view type into spec_view_types.
---@param data DataManager
---@param schema table View type schema
local function register_view_type(data, schema)
    if not schema or not schema.id then return end

    -- Serialize aliases to comma-separated string for SQL LIKE matching
    local aliases_str = nil
    if schema.aliases and #schema.aliases > 0 then
        aliases_str = "," .. table.concat(schema.aliases, ",") .. ","
    end

    data:execute(Queries.types.insert_view_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        aliases = aliases_str,
        inline_prefix = schema.inline_prefix,
        materializer_type = schema.materializer_type,
        counter_group = schema.counter_group,
        view_subtype_ref = schema.view_subtype_ref,
        needs_external_render = schema.needs_external_render and 1 or 0
    })
end

---Register a specification type into spec_specification_types.
---@param data DataManager
---@param schema table Specification type schema
local function register_specification_type(data, schema)
    if not schema or not schema.id then return end

    data:execute(Queries.types.insert_specification_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        is_default = schema.is_default and 1 or 0
    })

    -- Register implicit specification type aliases (title -> type mapping)
    if schema.implicit_aliases then
        for _, alias in ipairs(schema.implicit_aliases) do
            data:execute(Queries.types.insert_implicit_spec_alias, {
                alias = alias,
                type_id = schema.id
            })
        end
    end
end

---Register attribute definitions for a type schema.
---@param data DataManager
---@param schema table Type schema with attributes
local function register_attributes(data, schema)
    if not schema or not schema.attributes then return end

    for _, attr in ipairs(schema.attributes) do
        -- Ensure datatype exists
        local type_name = attr.type or DT.STRING
        if type_name == "INT" then
            type_name = DT.INTEGER
        end

        local datatype_id = attr.datatype_ref or type_name
        if type_name == DT.ENUM and not attr.datatype_ref then
            datatype_id = schema.id .. "_" .. attr.name
        end

        data:execute(Queries.types.insert_datatype, {
            id = datatype_id,
            name = datatype_id,
            type = type_name
        })

        data:execute(Queries.types.insert_attribute_definition, {
            id = schema.id .. "_" .. attr.name,
            owner = schema.id,
            long_name = attr.name,
            datatype = datatype_id,
            min = attr.min_occurs or 0,
            max = attr.max_occurs or 1,
            min_value = attr.min_value,
            max_value = attr.max_value
        })

        -- Insert enum values if applicable
        if attr.values then
            for i, val in ipairs(attr.values) do
                data:execute(Queries.types.insert_enum_value, {
                    id = datatype_id .. "_" .. val,
                    datatype = datatype_id,
                    key = val,
                    seq = i
                })
            end
        end
    end
end

---Propagate attribute definitions from parent types to child types through extends.
---After all modules are loaded, each child type receives copies of its parent's
---attribute definitions for any attribute the child does not already define.
---Iterates until stable to handle multi-level chains (e.g. HLR→TRACEABLE→SECTION).
---Child-defined attributes are never overwritten (INSERT OR IGNORE + UNIQUE constraint).
---@param data DataManager
local function propagate_inherited_attributes(data)
    -- Guard: some callers (e.g. unit-test stubs) may not implement query_all.
    if type(data.query_all) ~= "function" then return end

    local extends_rows = data:query_all([[
        SELECT identifier AS child_type, extends AS parent_type
        FROM spec_object_types
        WHERE extends IS NOT NULL
    ]], {})

    if not extends_rows or #extends_rows == 0 then return end

    local changed = true
    while changed do
        changed = false
        for _, row in ipairs(extends_rows) do
            local attrs = data:query_all([[
                SELECT sat.long_name, sat.datatype_ref,
                       sat.min_occurs, sat.max_occurs,
                       sat.min_value, sat.max_value
                FROM spec_attribute_types sat
                WHERE sat.owner_type_ref = :parent
                  AND NOT EXISTS (
                      SELECT 1 FROM spec_attribute_types sat2
                      WHERE sat2.owner_type_ref = :child
                        AND sat2.long_name = sat.long_name
                  )
            ]], { parent = row.parent_type, child = row.child_type })

            for _, attr in ipairs(attrs or {}) do
                data:execute([[
                    INSERT OR IGNORE INTO spec_attribute_types (
                        identifier, owner_type_ref, long_name, datatype_ref,
                        min_occurs, max_occurs, min_value, max_value
                    ) VALUES (
                        :id, :owner, :long_name, :datatype_ref,
                        :min_occurs, :max_occurs, :min_value, :max_value
                    )
                ]], {
                    id           = row.child_type .. "_" .. attr.long_name,
                    owner        = row.child_type,
                    long_name    = attr.long_name,
                    datatype_ref = attr.datatype_ref,
                    min_occurs   = attr.min_occurs or 0,
                    max_occurs   = attr.max_occurs or 1,
                    min_value    = attr.min_value,
                    max_value    = attr.max_value,
                })
            end
            -- Signal another pass only when the SELECT found rows to insert.
            -- Keeping this outside the per-attr loop ensures changed=true iff
            -- attrs were pending, preventing an infinite loop if INSERT OR IGNORE
            -- silently fails for a non-UNIQUE reason (e.g. FK violation).
            if attrs and #attrs > 0 then
                changed = true
            end
        end
    end
end

---Propagate link_selector from parent relation types to children through extends.
---After all modules are loaded, each child relation type that has extends but no
---link_selector receives the parent's link_selector value.
---@param data DataManager
local function propagate_inherited_relation_properties(data)
    if type(data.query_all) ~= "function" then return end

    local extends_rows = data:query_all([[
        SELECT identifier AS child_type, extends AS parent_type
        FROM spec_relation_types
        WHERE extends IS NOT NULL AND link_selector IS NULL
    ]], {})

    if not extends_rows or #extends_rows == 0 then return end

    for _, row in ipairs(extends_rows) do
        data:execute([[
            UPDATE spec_relation_types
            SET link_selector = (
                SELECT link_selector FROM spec_relation_types
                WHERE identifier = :parent
            )
            WHERE identifier = :child AND link_selector IS NULL
        ]], { parent = row.parent_type, child = row.child_type })
    end
end

---Register a specific type module into the IR database.
---Supports explicit type exports (M.float, M.relation, M.object, M.view, M.specification).
---@param data DataManager
---@param module TypeModule
function M.register_module(data, module)
    -- Priority 0: Base relation types (have both M.relation and M.resolve)
    if module.relation and module.resolve then
        -- Register resolver by type identifier (type-driven resolution)
        data:register_resolver(module.relation.id, module.resolve)
        -- Also register as a relation type in DB (so children can extend it)
        register_relation_type(data, module.relation)
        register_attributes(data, module.relation)
        return
    end

    -- Priority 1: Explicit type exports (new convention)
    -- Check for M.float, M.relation, M.object, M.view, M.specification keys
    if module.float then
        register_float_type(data, module.float)
        register_attributes(data, module.float)
        return
    elseif module.relation then
        register_relation_type(data, module.relation)
        register_attributes(data, module.relation)
        return
    elseif module.object then
        register_object_type(data, module.object)
        register_attributes(data, module.object)
        return
    elseif module.view then
        register_view_type(data, module.view)
        register_attributes(data, module.view)
        return
    elseif module.specification then
        register_specification_type(data, module.specification)
        register_attributes(data, module.specification)
        return
    end
end

---Resolve the filesystem path for a model's types directory.
---@param model_name string Model name (e.g., "default")
---@return string|nil path Absolute path to types directory, or nil if not found
---@return string|nil error Error message if path resolution failed
local function resolve_model_path(model_name)
    -- First check SPECCOMPILER_HOME if set
    local speccompiler_home = os.getenv("SPECCOMPILER_HOME")
    if speccompiler_home then
        local types_path = speccompiler_home .. "/models/" .. model_name .. "/types"
        local stat = fs.stat(types_path)
        if stat and stat.type == "directory" then
            return types_path
        end
    end

    -- Fall back to current working directory
    local cwd = fs.cwd()
    local types_path = cwd .. "/models/" .. model_name .. "/types"
    local stat = fs.stat(types_path)
    if stat and stat.type == "directory" then
        return types_path
    end
    return nil, "Types directory not found: " .. types_path
end

---Discover all type modules in a model's types directory.
---Scans only known categories and only single .lua files.
---@param types_path string Absolute path to types directory
---@return table|nil types Array of type paths like {"floats.figure", "objects.section"}
---@return string|nil error Error message if scanning failed
local function discover_types(types_path)
    local discovered = {}

    for _, category in ipairs(KNOWN_CATEGORIES) do
        local category_path = types_path .. "/" .. category
        local stat = fs.stat(category_path)

        if stat and stat.type == "directory" then
            local entries, err = fs.scandir(category_path)
            if not entries then
                return nil, "Failed to scan " .. category .. ": " .. tostring(err)
            end

            for _, entry in ipairs(entries) do
                -- Only .lua files, skip directories and init.lua
                if entry.type == "file" and entry.name:match("%.lua$") then
                    local type_name = entry.name:gsub("%.lua$", "")
                    if type_name ~= "init" then
                        table.insert(discovered, category .. "." .. type_name)
                    end
                end
            end
        end
    end

    table.sort(discovered) -- Deterministic load order
    return discovered
end

---Try to load a type module, supporting both single files and subdirectories.
---@param base_path string Base require path (e.g., "models.default.types")
---@param type_path string Type path (e.g., "floats.figure")
---@return boolean ok Whether loading succeeded
---@return table|string module_or_error The module or error message
local function try_load_type(base_path, type_path)
    local full_path = base_path .. "." .. type_path

    -- First, try direct path (e.g., models.default.types.floats.figure)
    local ok, module = pcall(require, full_path)
    if ok then
        return true, module
    end

    -- If that fails, try subdirectory with init.lua (e.g., models.default.types.floats.figure.init)
    local init_path = full_path .. ".init"
    ok, module = pcall(require, init_path)
    if ok then
        return true, module
    end

    -- Both failed, return the original error with details
    return false, "Failed to load type module: " .. full_path .. " (tried both .lua and /init.lua). Error: " .. tostring(module)
end

---Load all modules from a directory and register them into Data and Pipeline.
---@param data DataManager
---@param pipeline Pipeline
---@param model_name string Name of the model (e.g. 'default')
function M.load_model(data, pipeline, model_name)
    local base_path = "models." .. model_name .. ".types"

    -- Resolve filesystem path
    local types_path, path_err = resolve_model_path(model_name)
    if not types_path then
        error("Failed to locate model '" .. model_name .. "': " .. tostring(path_err))
    end

    -- Discover types
    local types, discover_err = discover_types(types_path)
    if not types then
        error("Failed to discover types for '" .. model_name .. "': " .. tostring(discover_err))
    end

    -- Load and register each type
    for _, type_path in ipairs(types) do
        local ok, module = try_load_type(base_path, type_path)
        if ok then
            M.register_module(data, module)
            if module.handler then
                pipeline:register_handler(module.handler)
            end
        else
            error(module) -- module contains the error message
        end
    end

    -- After all types are registered, propagate inherited attributes so that
    -- attributes defined on base types (e.g. TRACEABLE.status) are visible
    -- on child types (e.g. HLR) for validation and casting.
    propagate_inherited_attributes(data)
    propagate_inherited_relation_properties(data)
end

return M
