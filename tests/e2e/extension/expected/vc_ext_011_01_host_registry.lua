-- Test oracle for VC-EXT-011: Host registry descriptor contract (HLR-EXT-011)
--
-- Exercises contract.registry in isolation with a mock data manager that
-- records execute() calls:
--   1. a valid descriptor dual-emits its type row + indexes hooks + extends
--   2. unknown kind / missing schema.id / wrong-kind hook / non-function hook
--      all error loudly and precisely
--   3. hooks inherit through the extends chain (generalized get_relation_handler)
--   4. relation rows dual-emit and resolve/render_link index
--   5. re-registering the same id is safe (INSERT OR REPLACE idempotence)

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local registry = require("contract.registry")

    -- Mock data manager: records execute() calls; queries return empty.
    local function make_mock()
        local calls = {}
        return {
            calls = calls,
            execute = function(_, sql, params)
                calls[#calls + 1] = { sql = sql, params = params }
            end,
            query_all = function() return {} end,
            query_one = function() return nil end,
            register_resolver = function() end,
            db = { exec_sql = function() end },
        }
    end

    local function inserted(mock, table_name, identifier)
        for _, c in ipairs(mock.calls) do
            if tostring(c.sql):find(table_name, 1, true)
                and c.params and c.params.identifier == identifier then
                return true
            end
        end
        return false
    end

    -- 1. Valid object descriptor: dual-emit + index + extends
    local mock = make_mock()
    local host = registry.new{ data = mock }
    host:register{
        kind = "object",
        schema = {
            id = "HLR", long_name = "High-Level Requirement", extends = "TRACEABLE",
            attributes = { { name = "priority", type = "ENUM", values = { "High", "Low" } } },
        },
        hooks = { render = function() return "r" end },
    }
    if type(host:get_hook("object", "HLR", "render")) ~= "function" then
        err("render hook not indexed for object/HLR")
    end
    if host:extends_of("object", "HLR") ~= "TRACEABLE" then
        err("extends not captured for object/HLR")
    end
    if not inserted(mock, "spec_object_types", "HLR") then
        err("no INSERT into spec_object_types for HLR (dual-emit)")
    end

    -- 2. Malformed: unknown kind
    local ok1, e1 = pcall(function() host:register{ kind = "bogus", schema = { id = "X" } } end)
    if ok1 then err("unknown kind should error")
    elseif not tostring(e1):find("bogus", 1, true) then
        err("unknown-kind error should name the kind: " .. tostring(e1)) end

    -- 3. Malformed: missing schema.id
    local ok2, e2 = pcall(function() host:register{ kind = "object", schema = {} } end)
    if ok2 then err("missing schema.id should error")
    elseif not tostring(e2):find("schema.id", 1, true) then
        err("missing-id error should mention schema.id: " .. tostring(e2)) end

    -- 4. Malformed: hook on wrong kind (resolve is not valid for object)
    local ok3, e3 = pcall(function()
        host:register{ kind = "object", schema = { id = "O2" }, hooks = { resolve = function() end } }
    end)
    if ok3 then err("resolve hook on object should error")
    elseif not tostring(e3):find("resolve", 1, true) then
        err("wrong-kind-hook error should name the hook: " .. tostring(e3)) end

    -- 5. Malformed: non-function hook
    if pcall(function()
        host:register{ kind = "object", schema = { id = "O3" }, hooks = { render = "nope" } }
    end) then
        err("non-function hook should error")
    end

    -- 6. extends-chain hook inheritance (generalizes get_relation_handler)
    local mock2 = make_mock()
    local host2 = registry.new{ data = mock2 }
    host2:register{ kind = "object", schema = { id = "BASE" }, hooks = { render = function() return "base" end } }
    host2:register{ kind = "object", schema = { id = "CHILD", extends = "BASE" } }
    if host2:get_hook("object", "CHILD", "render") ~= nil then
        err("CHILD should not own a render hook")
    end
    if type(host2:get_hook_inherited("object", "CHILD", "render")) ~= "function" then
        err("CHILD should inherit BASE.render via the extends chain")
    end

    -- 7. relation: role inferred from resolve hook; dual-emit into relation table
    local mock3 = make_mock()
    local host3 = registry.new{ data = mock3 }
    host3:register{
        kind = "relation",
        schema = { id = "REALIZES", source_type_ref = "LLR", target_type_ref = "HLR" },
        hooks = { resolve = function() end, render_link = function() end },
    }
    if type(host3:get_hook("relation", "REALIZES", "resolve")) ~= "function" then
        err("resolve hook not indexed for relation/REALIZES")
    end
    if not inserted(mock3, "spec_relation_types", "REALIZES") then
        err("no INSERT into spec_relation_types for REALIZES")
    end

    -- 8. dual-emit idempotence: re-registering REALIZES with the SAME full
    -- schema must (a) not error and (b) emit an IDENTICAL row -- same INSERT
    -- params -- proving INSERT OR REPLACE re-emits identical rows rather than
    -- nulling columns. (case 7 already registered REALIZES once.)
    local realizes_schema = { id = "REALIZES", source_type_ref = "LLR", target_type_ref = "HLR" }
    local function relation_insert_params(m)
        local found = {}
        for _, c in ipairs(m.calls) do
            if tostring(c.sql):find("spec_relation_types", 1, true)
                and c.params and c.params.identifier == "REALIZES" then
                found[#found + 1] = c.params
            end
        end
        return found
    end
    if not pcall(function()
        host3:register{ kind = "relation", schema = realizes_schema, hooks = { resolve = function() end } }
    end) then
        err("re-registering REALIZES should be safe (INSERT OR REPLACE)")
    end
    local rparams = relation_insert_params(mock3)
    if #rparams < 2 then
        err("expected >=2 spec_relation_types inserts for REALIZES, got " .. #rparams)
    else
        local a, b = rparams[#rparams - 1], rparams[#rparams]
        local keys = { "identifier", "long_name", "description", "extends", "link_selector",
                       "source_attribute", "source_type_ref", "target_type_ref", "is_structural" }
        for _, k in ipairs(keys) do
            if a[k] ~= b[k] then
                err(("dual-emit not idempotent: relation param '%s' differs (%s vs %s)")
                    :format(k, tostring(a[k]), tostring(b[k])))
            end
        end
    end

    if #errors > 0 then
        return false, "Host registry validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
