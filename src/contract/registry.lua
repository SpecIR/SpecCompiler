---Host Engine registry for the Descriptor Plugin contract
---(HLR-EXT-003/004/011).
---
---One `host` object is built per `engine.run_project`. It is the single loader
---and the single hook index: it walks each model, reads every plugin module's
---descriptor `{kind, schema, [hooks]}`, and for each descriptor:
---
---  a. INSERT_FN[kind](data, schema) -- emit the type row (INSERT OR REPLACE,
---     idempotent across model layering).
---  b. capture schema.extends into _extends[kind][id] (attribute + hook
---     inheritance, walked by get_hook_inherited).
---  c. eager-index each present hook into _caps[kind][id][hook] = fn -- the one
---     index every consumer reads via get_hook / get_hook_inherited.
---
---@module contract.registry

local uv = require("luv")
local DT = require("core.datatypes")
local Queries = require("db.queries")

local M = {}

-- ===========================================================================
-- Discovery: walk a model's type-category directories.
-- ===========================================================================

local KNOWN_CATEGORIES = { "objects", "floats", "views", "relations", "specifications" }
local CATEGORY_KIND = {
    objects        = "object",
    floats         = "float",
    views          = "view",
    relations      = "relation",
    specifications = "specification",
}

local function create_fs_adapter(uv_lib)
    return {
        cwd = function() return uv_lib.cwd() end,
        stat = function(path) return uv_lib.fs_stat(path) end,
        scandir = function(path)
            local req, err = uv_lib.fs_scandir(path)
            if not req then return nil, err end
            local entries = {}
            while true do
                local name, entry_type = uv_lib.fs_scandir_next(req)
                if not name then break end
                table.insert(entries, { name = name, type = entry_type })
            end
            return entries
        end,
    }
end

local fs = create_fs_adapter(uv)

---Probe SPECCOMPILER_HOME then cwd for an existing models/<...> directory.
---(The SPECCOMPILER_HOME read is the one env read still permitted -- toolchain
---bootstrap.)
---@param rel string Path relative to each base (e.g. "models/abnt/types")
---@return string|nil dir First existing directory, or nil
local function probe_model_path(rel)
    local home = os.getenv("SPECCOMPILER_HOME")
    local candidates = {}
    if home then candidates[#candidates + 1] = home .. "/" .. rel end
    candidates[#candidates + 1] = fs.cwd() .. "/" .. rel
    for _, p in ipairs(candidates) do
        local st = fs.stat(p)
        if st and st.type == "directory" then return p end
    end
    return nil
end

---Resolve a model subdirectory (e.g. "types").
local function model_dir(model_name, subdir)
    return probe_model_path("models/" .. model_name .. "/" .. subdir)
end

---Resolve a model's root directory (models/<name>/). Used to fail loudly when
---a requested model is entirely absent.
local function model_root(model_name)
    return probe_model_path("models/" .. model_name)
end

-- ===========================================================================
-- Type-row INSERT bodies (one per kind). All inserts are INSERT OR REPLACE
-- (idempotent across model layering).
-- ===========================================================================

---Wrap an aliases array as the CSV-with-sentinels storage format
---(",a,b," -- the leading/trailing commas make LIKE matching exact).
---@param aliases table|nil
---@return string|nil
local function aliases_csv(aliases)
    if aliases and #aliases > 0 then
        return "," .. table.concat(aliases, ",") .. ","
    end
    return nil
end

---Register attribute definitions for a type schema.
local function register_attributes(data, schema)
    if not schema or not schema.attributes then return end

    for _, attr in ipairs(schema.attributes) do
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

local function insert_float(data, schema)
    local aliases_str = aliases_csv(schema.aliases)
    data:execute(Queries.types.insert_float_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        caption_format = schema.caption_format or schema.id,
        counter_group = schema.counter_group or schema.id,
        aliases = aliases_str,
        needs_external_render = schema.needs_external_render and 1 or 0
    })
    register_attributes(data, schema)
end

local function insert_relation(data, schema)
    data:execute(Queries.types.insert_relation_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        link_selector = schema.link_selector,
        source_attribute = schema.source_attribute,
        source_type_ref = schema.source_type_ref,
        target_type_ref = schema.target_type_ref,
        is_structural = schema.is_structural and 1 or 0
    })
    register_attributes(data, schema)
end

local function insert_object(data, schema)
    local aliases_str = aliases_csv(schema.aliases)
    -- The container/numbering FLAGS below are LEAF-LOCAL by design: unlike
    -- attributes (which propagate_inherited_attributes walks down the extends
    -- chain), is_composite/is_default/numbered/pid_prefix/pid_format are read
    -- only from the type's OWN schema and are NOT inherited from a base type. A
    -- subtype routinely needs different container semantics than its base -- e.g.
    -- TRACEABLE extends SECTION (is_composite=true) but is a leaf, so HLR/VC must
    -- stay is_composite=false. Declare these on the concrete type that needs them.
    data:execute(Queries.types.insert_object_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        is_composite = schema.is_composite and 1 or 0,
        is_required = schema.is_required and 1 or 0,
        is_default = schema.is_default and 1 or 0,
        pid_prefix = schema.pid_prefix,
        pid_format = schema.pid_format,
        aliases = aliases_str
    })
    if schema.implicit_aliases then
        for _, alias in ipairs(schema.implicit_aliases) do
            data:execute(Queries.types.insert_implicit_alias, {
                alias = alias,
                type_id = schema.id,
                alias_level = schema.implicit_alias_level
            })
        end
    end
    register_attributes(data, schema)
end

local function insert_view(data, schema)
    local aliases_str = aliases_csv(schema.aliases)
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
    register_attributes(data, schema)
end

local function insert_specification(data, schema)
    data:execute(Queries.types.insert_specification_type, {
        identifier = schema.id,
        long_name = schema.long_name or schema.id,
        description = schema.description or "",
        extends = schema.extends,
        is_default = schema.is_default and 1 or 0
    })
    if schema.implicit_aliases then
        for _, alias in ipairs(schema.implicit_aliases) do
            data:execute(Queries.types.insert_implicit_spec_alias, {
                alias = alias,
                type_id = schema.id
            })
        end
    end
    register_attributes(data, schema)
end

-- kind -> insert function. New extension point = new table entry (no core
-- control-flow edits). The verification kind has no type row (false); it is
-- handled by its own message hook + the policy_key registry.
local INSERT_FN = {
    object        = insert_object,
    float         = insert_float,
    view          = insert_view,
    relation      = insert_relation,
    specification = insert_specification,
    verification  = false,
}

---Propagate inherited attributes through the object `extends` chain.
local function propagate_inherited_attributes(data)
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
            if attrs and #attrs > 0 then
                changed = true
            end
        end
    end
end

-- ===========================================================================
-- Contract metadata: valid kinds and which hooks each kind may declare.
-- "Role is inferred from which hooks are present"; an invalid hook for a kind
-- is a loud register-time error.
-- ===========================================================================

local VALID_KINDS = {
    object = true, float = true, view = true, relation = true,
    specification = true, verification = true,
}

-- Per-kind hook contract. Each entry maps a hook NAME to:
--   tier     "render" -- runs during the EMIT walk; sole arg is the frozen
--                        render ctx (has pandoc/format; ctx.subject is the
--                        Pandoc element).
--            "data"   -- runs in a data/lifecycle phase (TRANSFORM/ANALYZE/
--                        external-render); sole arg is the frozen DATA ctx
--                        (no pandoc/format; dctx.subject carries the payload).
--   returns  the TYPE the hook must return: "ast" (a Pandoc element or an
--            array of them -- table or userdata) or "string". nil is always
--            an accepted return (meaning "nothing produced / fall back")
--            unless `required` is set. Checked at dispatch time: a wrong-typed
--            return is a loud error naming kind/id/hook instead of a confusing
--            downstream failure.
-- The hook name selects the context; there is no second descriptor bag.
local ALLOWED_HOOKS = {
    object        = { render = { tier = "render", returns = "ast" } },
    float         = { render        = { tier = "render", returns = "ast" },
                      transform     = { tier = "data", returns = "string" },
                      prepare_task  = { tier = "data", returns = "ast" },     -- task table
                      handle_result = { tier = "data" } },                    -- return unused
    view          = { render       = { tier = "render", returns = "ast" },   -- inlines
                      render_block = { tier = "render", returns = "ast" },   -- one block
                      dataset      = { tier = "data", returns = "ast" },     -- dataset table
                      build_block  = { tier = "data", returns = "ast" } },   -- one block
    relation      = { render_link = { tier = "render", returns = "string" },
                      resolve     = { tier = "data", returns = "ast" } },    -- {target, ambiguous}
    specification = { render = { tier = "render", returns = "ast" } },
    verification  = { message = { tier = "render", returns = "string", required = true } },
}

---Dispatch-time postcondition for a hook's first return value, per the
---`returns` contract above. Extra return values pass through untouched.
local function check_hook_return(kind, id, hookname, contract, ...)
    local first = ...
    if first == nil then
        if contract.required then
            error(("hook %s/%s.%s must return a %s, got nil")
                :format(kind, id, hookname, contract.returns), 3)
        end
        return ...
    end
    local t = type(first)
    if contract.returns == "string" then
        if t ~= "string" then
            error(("hook %s/%s.%s must return a string, got %s")
                :format(kind, id, hookname, t), 3)
        end
    elseif contract.returns == "ast" then
        if t ~= "table" and t ~= "userdata" then
            error(("hook %s/%s.%s must return a table/Pandoc value, got %s")
                :format(kind, id, hookname, t), 3)
        end
    end
    return ...
end

-- The only keys a descriptor table may carry at the top level. ALL behavior --
-- including pipeline phase participation (on_<phase>) -- belongs under `hooks`.
-- Enforced in Host:register so a function smuggled onto any other top-level key
-- fails at load.
local ALLOWED_TOP_LEVEL_KEYS = {
    kind = true, schema = true, hooks = true,
}

local KNOWN_PHASES = {
    initialize = true, analyze = true, transform = true, verify = true, emit = true,
}

---Phase hooks (on_<phase>) are allowed in `hooks` on any kind. They are NOT
---indexed into _caps: the host registers them as a pipeline handler (named
---`<lower(schema.id)>_handler`, ordered by `schema.phase_prerequisites`) and
---the pipeline dispatches them per phase.
local function is_phase_hook(name)
    local phase = name:match("^on_(%a+)$")
    return phase ~= nil and KNOWN_PHASES[phase] == true
end

-- ===========================================================================
-- Descriptor recognition.
-- ===========================================================================

---A plugin module returns its descriptor table directly:
---`{ kind, schema, hooks, [phase_handler] }`. A module that is not a descriptor
---(e.g. a shared data table such as verification_views/sql.lua) yields nil and
---is skipped by the loader.
---@param module table the required plugin module
---@return table|nil descriptor
local function as_descriptor(module)
    if type(module.kind) == "string" and type(module.schema) == "table" then
        return module
    end
    return nil
end

-- ===========================================================================
-- Host object.
-- ===========================================================================

local Host = {}
Host.__index = Host

---Create a host. Only `data` is required for registration; pipeline/config/
---log/diagnostics are carried for later steps.
---@param opts table { data, pipeline?, config?, log?, diagnostics? }
---@return table host
function M.new(opts)
    opts = opts or {}
    assert(type(opts.data) == "table", "registry.new requires a data manager")
    return setmetatable({
        data = opts.data,
        pipeline = opts.pipeline,
        log = opts.log,
        diagnostics = opts.diagnostics,
        _caps = {},        -- _caps[kind][id][hook] = fn
        _extends = {},     -- _extends[kind][id] = parent id
        _descriptors = {}, -- _descriptors[kind][id] = descriptor
        -- Verification-view registry (ordered + by policy_key) with override/
        -- disabled semantics (HLR-EXT-012).
        _verification_views = {},   -- ordered array of {view, policy_key, sql, message, disabled}
        _verification_by_key = {},  -- policy_key -> entry (override/dedup)
        -- Inline-view prefix -> view id, built at registration from a view's
        -- inline_prefix + aliases.
        _view_prefixes = {},        -- lowercased prefix -> view id
    }, Host)
end

---Register a single descriptor: validate, emit the type row, capture extends,
---and eager-index the hooks. Loud on malformed input.
---@param descriptor table { kind, schema = { id, ... }, [hooks = { ... }] } -- hooks optional; pure-schema types omit it
---@return table host
function Host:register(descriptor)
    if type(descriptor) ~= "table" then
        error("host:register expects a descriptor table, got " .. type(descriptor), 2)
    end
    local kind = descriptor.kind
    if not VALID_KINDS[kind] then
        error("host:register: unknown kind '" .. tostring(kind) .. "'", 2)
    end
    local schema = descriptor.schema
    if type(schema) ~= "table" then
        error("host:register(" .. kind .. "): schema must be a table", 2)
    end
    local id = schema.id
    if type(id) ~= "string" or id == "" then
        error("host:register(" .. kind .. "): schema.id is required", 2)
    end

    local hooks = descriptor.hooks or {}
    if type(hooks) ~= "table" then
        error(("host:register(%s/%s): hooks must be a table"):format(kind, id), 2)
    end
    for hookname, fn in pairs(hooks) do
        if type(fn) ~= "function" then
            error(("host:register(%s/%s): hook '%s' must be a function, got %s")
                :format(kind, id, tostring(hookname), type(fn)), 2)
        end
        if not (ALLOWED_HOOKS[kind][hookname] or is_phase_hook(hookname)) then
            error(("host:register(%s/%s): hook '%s' is not valid for kind '%s'")
                :format(kind, id, tostring(hookname), kind), 2)
        end
    end

    if descriptor.phase_handler ~= nil then
        error(("host:register(%s/%s): `phase_handler` was folded into `hooks` -- "
            .. "declare on_<phase> functions in `hooks` and cross-handler ordering "
            .. "in `schema.phase_prerequisites`"):format(kind, id), 2)
    end

    -- Behavior lives ONLY under `hooks`. A function hung off a top-level descriptor key would
    -- silently never fire -- the host indexes `hooks`, never top-level keys -- so
    -- reject it loudly. This is exactly the carve-out that hid the abnt list-view
    -- dispatch (a `generate`/`render` smuggled in beside `hooks = {}`).
    for key, value in pairs(descriptor) do
        if type(value) == "function" and not ALLOWED_TOP_LEVEL_KEYS[key] then
            error(("host:register(%s/%s): top-level key '%s' is a function; behavior "
                .. "must live in `hooks` (the host never dispatches top-level keys)")
                :format(kind, id, tostring(key)), 2)
        end
    end

    -- A float renders internally (render) XOR externally (prepare_task/
    -- handle_result) -- declaring both is a contradiction.
    if kind == "float" and hooks.render
        and (hooks.prepare_task or hooks.handle_result) then
        error(("host:register(float/%s): a float may not declare both an internal "
            .. "render hook and external prepare_task/handle_result hooks"):format(id), 2)
    end

    -- a. emit the type row (idempotent INSERT OR REPLACE)
    local insert = INSERT_FN[kind]
    if insert then
        insert(self.data, schema)
    end

    -- b. capture extends (attribute + hook inheritance)
    self._extends[kind] = self._extends[kind] or {}
    self._extends[kind][id] = schema.extends

    -- c. eager hook index -- the one index every consumer reads via get_hook /
    -- get_hook_inherited. Every declared hook is indexed uniformly (including a
    -- relation's `resolve`, which is ALSO wired to the resolver registry in step d
    -- for its ANALYZE-phase dispatch -- the index keeps get_hook uniform).
    self._caps[kind] = self._caps[kind] or {}
    self._caps[kind][id] = self._caps[kind][id] or {}
    for hookname, fn in pairs(hooks) do
        -- Phase hooks are pipeline-dispatched (see _register_phase_handler),
        -- never get_hook-dispatched; keep them out of the capability index.
        if not is_phase_hook(hookname) then
            local contract = ALLOWED_HOOKS[kind][hookname]
            if contract and contract.returns then
                local raw = fn
                self._caps[kind][id][hookname] = function(...)
                    return check_hook_return(kind, id, hookname, contract, raw(...))
                end
            else
                self._caps[kind][id][hookname] = fn
            end
        end
    end

    -- d. a relation's `resolve` DATA hook IS the type's resolver. The resolver
    -- registry stores the INDEXED hook (so the return-contract check applies on
    -- this path too); the relation analyzer calls it with the frozen DATA ctx
    -- and reads the single {target, ambiguous} return -- one calling convention
    -- everywhere.
    if kind == "relation" and type(hooks.resolve) == "function"
        and type(self.data.register_resolver) == "function" then
        self.data:register_resolver(id, self._caps[kind][id].resolve)
    end

    -- e. verification descriptors feed the ordered policy_key registry
    -- (override + disabled semantics preserved).
    if kind == "verification" then
        self:_register_verification(schema, hooks.message)
    end

    -- f. a view's inline_prefix + aliases populate the prefix -> id map the
    -- inline view dispatcher (emit_view) uses to route `prefix:` Code elements.
    if kind == "view" then
        local function add_prefix(p)
            if type(p) == "string" and p ~= "" then
                self._view_prefixes[p:lower()] = id
            end
        end
        add_prefix(schema.inline_prefix)
        if type(schema.aliases) == "table" then
            for _, a in ipairs(schema.aliases) do add_prefix(a) end
        end
    end

    self._descriptors[kind] = self._descriptors[kind] or {}
    self._descriptors[kind][id] = descriptor

    return self
end

---Register a verification view into the ordered policy_key registry with
---override/disabled semantics: a `disabled` entry removes any existing entry for
---its policy_key; otherwise a repeat policy_key replaces in place (model
---layering) and a new one appends.
---@param schema table { policy_key, view, sql, disabled }
---@param message_fn function|nil row -> message
function Host:_register_verification(schema, message_fn)
    local policy_key = schema.policy_key
    if not policy_key then return end

    if schema.disabled then
        if self._verification_by_key[policy_key] then
            for i, existing in ipairs(self._verification_views) do
                if existing.policy_key == policy_key then
                    table.remove(self._verification_views, i)
                    break
                end
            end
            self._verification_by_key[policy_key] = nil
        end
        return
    end

    local entry = {
        view = schema.view,
        policy_key = policy_key,
        sql = schema.sql,
        message = message_fn,
        disabled = schema.disabled,
    }

    if self._verification_by_key[policy_key] then
        for i, existing in ipairs(self._verification_views) do
            if existing.policy_key == policy_key then
                self._verification_views[i] = entry
                break
            end
        end
    else
        table.insert(self._verification_views, entry)
    end
    self._verification_by_key[policy_key] = entry
end

---Ordered verification views (read by verify_handler).
---@return table[] entries
function Host:get_verification_views()
    return self._verification_views
end

---Create all verification SQL views in the database (CREATE VIEW IF NOT EXISTS,
---so idempotent).
---@param data DataManager
function Host:create_verification_views(data)
    for _, entry in ipairs(self._verification_views) do
        if entry.sql then
            data.db:exec_sql(entry.sql)
        end
    end
end

---Read the `requires:` list from a model's model.yaml manifest (HLR-EXT-010).
---Minimal parse, no YAML library: flow style (`requires: [charts]`) or block
---style (`requires:` followed by `- name` lines). Absent manifest or absent
---key -> empty list.
---@param model_name string
---@return table requires Array of required model names
local function manifest_requires(model_name)
    local root = model_root(model_name)
    if not root then return {} end
    local f = io.open(root .. "/model.yaml", "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()

    local reqs = {}
    local flow = content:match("\nrequires:[ \t]*%[([^%]]*)%]")
        or content:match("^requires:[ \t]*%[([^%]]*)%]")
    if flow then
        for name in flow:gmatch("[%w_%-]+") do reqs[#reqs + 1] = name end
        return reqs
    end
    local block = content:match("\nrequires:[ \t]*\n(.-)\n%S")
        or content:match("\nrequires:[ \t]*\n(.*)$")
    if block then
        for line in block:gmatch("[^\n]+") do
            local name = line:match("^%s*%-%s*([%w_%-]+)")
            if name then reqs[#reqs + 1] = name end
        end
    end
    return reqs
end

---Load a model: its manifest-declared requirements (recursively), then its
---type categories and verification views. Idempotent per model name, so a
---model required by several others (or required and also set as template)
---loads once. A missing required model is a loud error.
---@param model_name string
---@return table host
function Host:load_model(model_name)
    self._loaded_models = self._loaded_models or {}
    if self._loaded_models[model_name] then return self end
    self._loaded_models[model_name] = true

    local root = model_root(model_name)
    if not root then
        error("Failed to locate model '" .. tostring(model_name) .. "'")
    end

    for _, req in ipairs(manifest_requires(model_name)) do
        if req ~= model_name and req ~= "default" then
            self:load_model(req)
        end
    end
    -- model_root honours SPECCOMPILER_HOME then cwd, but `require` only searches
    -- package.path. When the model lives outside SPECCOMPILER_HOME (a
    -- project-local models/ directory), extend package.path so the
    -- "models.<name>.*" requires below resolve against the model's actual base.
    local base = root:sub(1, #root - #("/models/" .. model_name))
    local extra = base .. "/?.lua;" .. base .. "/?/init.lua"
    if not package.path:find(extra, 1, true) then
        package.path = package.path .. ";" .. extra
    end
    self:_load_types(model_name)
    self:_load_verification_views(model_name)
    return self
end

---Register a descriptor's pipeline PHASE participation. on_<phase> functions
---live in `hooks` beside the behavior hooks; the handler is registered under
---the derived name `<lower(schema.id)>_handler` (which preserves the legacy
---phase_handler names, so existing cross-handler prerequisite references keep
---resolving) with ordering from `schema.phase_prerequisites`. Guarded against
---an already-present handler of that name (intra-host idempotence across
---model overlays).
---@param descriptor table validated descriptor ({kind, schema, hooks})
function Host:_register_phase_handler(descriptor)
    if not self.pipeline then return end

    local handler = nil
    for name, fn in pairs(descriptor.hooks or {}) do
        if is_phase_hook(name) then
            handler = handler or {}
            handler[name] = fn
        end
    end
    if not handler then return end

    handler.name = descriptor.schema.id:lower() .. "_handler"
    handler.prerequisites = descriptor.schema.phase_prerequisites or {}

    if self.pipeline.handlers and self.pipeline.handlers[handler.name] then return end
    self.pipeline:register_handler(handler)
end

---Walk a model's type categories, read each module's descriptor, and register
---them.
---@param model_name string
---@return table host
function Host:_load_types(model_name)
    local types_path = model_dir(model_name, "types")
    if not types_path then return self end  -- model has no types directory

    for _, category in ipairs(KNOWN_CATEGORIES) do
        local kind = CATEGORY_KIND[category]
        local category_path = types_path .. "/" .. category
        local stat = fs.stat(category_path)
        if stat and stat.type == "directory" then
            local entries = fs.scandir(category_path) or {}
            local names = {}
            for _, e in ipairs(entries) do
                if e.type == "file" and e.name:match("%.lua$") then
                    local n = e.name:gsub("%.lua$", "")
                    if n ~= "init" then names[#names + 1] = n end
                end
            end
            table.sort(names)  -- deterministic load order

            for _, n in ipairs(names) do
                local req = "models." .. model_name .. ".types." .. category .. "." .. n
                local ok, module = pcall(require, req)
                if not ok then
                    ok, module = pcall(require, req .. ".init")
                end
                if ok and type(module) == "table" then
                    local descriptor = as_descriptor(module)
                    if descriptor then
                        if descriptor.kind ~= kind then
                            error(("type module %s declares kind '%s' but lives in the '%s' category (expected '%s')")
                                :format(req, tostring(descriptor.kind), category, kind))
                        end
                        self:register(descriptor)
                        self:_register_phase_handler(descriptor)
                    end
                elseif not ok then
                    -- Views are optional extensions (warn + skip); every other
                    -- category is a hard load error.
                    if category == "views" then
                        io.stderr:write("WARN  Skipping view module: " .. req .. " (load failed)\n")
                    else
                        error("Failed to load type module: " .. req .. ": " .. tostring(module))
                    end
                end
            end
        end
    end

    return self
end

---Walk a model's verification_views directory and register each verification
---descriptor through the same as_descriptor/register path as every other kind.
---sql.lua returns a plain SQL-string table (no kind/schema), so as_descriptor
---returns nil for it and it is skipped.
---@param model_name string
---@return table host
function Host:_load_verification_views(model_name)
    local vv_path = model_dir(model_name, "verification_views")
    if not vv_path then return self end

    local entries = fs.scandir(vv_path) or {}
    local names = {}
    for _, e in ipairs(entries) do
        if e.type == "file" and e.name:match("%.lua$") then
            names[#names + 1] = e.name:gsub("%.lua$", "")
        end
    end
    table.sort(names)  -- deterministic load order

    for _, n in ipairs(names) do
        local req = "models." .. model_name .. ".verification_views." .. n
        local ok, module = pcall(require, req)
        -- A require failure is a hard error, not a silent skip.
        if not ok then
            error("Failed to load verification view module: " .. req .. ": " .. tostring(module))
        end
        if type(module) == "table" then
            local descriptor = as_descriptor(module)
            if descriptor then self:register(descriptor) end
        end
    end

    return self
end

---Required-hook validation, run after every model is loaded (so hooks inherited
---via the extends chain are visible). A view that extends TABLE_VIEW relies on the
---shared render_block dispatching the concrete view's `build_block`; if neither the
---view nor an ancestor provides one, the view silently renders nothing. Catch that
---at load instead of at render time.
function Host:_assert_required_hooks()
    for id in pairs(self._descriptors.view or {}) do
        local cur, seen, extends_table_view = self:extends_of("view", id), {}, false
        while cur and not seen[cur] do
            if cur == "TABLE_VIEW" then extends_table_view = true; break end
            seen[cur] = true
            cur = self:extends_of("view", cur)
        end
        if extends_table_view and not self:get_hook_inherited("view", id, "build_block") then
            error(("host:finalize: view '%s' extends TABLE_VIEW but provides no "
                .. "`build_block` hook (its render would produce nothing)"):format(id), 2)
        end
    end
end

---Finalize the host once all models are loaded: propagate inherited attributes
---through the extends chain, create the verification SQL views, and assert that
---every kind's required hooks are present.
---@return table host
function Host:finalize()
    propagate_inherited_attributes(self.data)
    self:create_verification_views(self.data)
    self:_assert_required_hooks()
    return self
end

-- --- Accessors (the hook index read by every consumer) ---

---@return function|nil
function Host:get_hook(kind, id, hook)
    local k = self._caps[kind]; if not k then return nil end
    local i = k[id]; if not i then return nil end
    return i[hook]
end

---@return table|nil
function Host:get_descriptor(kind, id)
    local k = self._descriptors[kind]
    return k and k[id] or nil
end

---@return string|nil parent id
function Host:extends_of(kind, id)
    local k = self._extends[kind]
    return k and k[id] or nil
end

---Resolve a hook walking the `extends` chain (used for any kind, e.g. relation
---render_link inherited from LABEL_REF/PID_REF roots).
---@return function|nil
function Host:get_hook_inherited(kind, id, hook)
    local seen = {}
    local current = id
    while current and not seen[current] do
        local fn = self:get_hook(kind, current, hook)
        if fn then return fn end
        seen[current] = true
        current = self:extends_of(kind, current)
    end
    return nil
end

---Inline view prefixes mapped to their view id, longest-prefix-first so a more
---specific prefix (e.g. "sigla_list") is matched before a shorter one ("sigla").
---@return table[] list of { prefix = string, id = string }
function Host:get_inline_views()
    local list = {}
    for prefix, id in pairs(self._view_prefixes) do
        list[#list + 1] = { prefix = prefix, id = id }
    end
    table.sort(list, function(a, b)
        if #a.prefix ~= #b.prefix then return #a.prefix > #b.prefix end
        return a.prefix < b.prefix
    end)
    return list
end

-- ===========================================================================
-- Module-level "current host" handle (set by the engine; read by consumers in
-- later steps). Reset per run.
-- ===========================================================================

function M.set_current(host) M._current = host end
function M.current() return M._current end
function M.reset() M._current = nil end

return M
