-- Test oracle for VC-EXT-012: verification descriptor + host registry (HLR-EXT-012)
--
-- The host owns the ordered policy_key verification registry. Verifies:
--   1. register preserves insertion order and carries the message hook
--   2. a repeat policy_key overrides IN PLACE (model layering, order kept)
--   3. disabled=true removes the entry for its policy_key
--   4. create_analyze_queries execs each entry's SQL
--   5. a non-message hook on the verification kind errors loudly

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local registry = require("contract.registry")

    local exec_sqls = {}
    local mock = {
        execute = function() end,
        query_all = function() return {} end,
        query_one = function() return nil end,
        register_resolver = function() end,
        db = { exec_sql = function(_, sql) exec_sqls[#exec_sqls + 1] = sql end },
    }
    local host = registry.new{ data = mock }

    local function vdesc(pk, view, sql, disabled, msg)
        return {
            kind = "analyze",
            schema = { id = pk, policy_key = pk, view = view, sql = sql, disabled = disabled },
            hooks = msg and { message = msg } or {},
        }
    end

    -- 1. register A, B, C -> ordered, with message hooks
    host:register(vdesc("pk_a", "v_a", "CREATE VIEW IF NOT EXISTS v_a AS SELECT 1", nil, function() return "a" end))
    host:register(vdesc("pk_b", "v_b", "CREATE VIEW IF NOT EXISTS v_b AS SELECT 1", nil, function() return "b" end))
    host:register(vdesc("pk_c", "v_c", "CREATE VIEW IF NOT EXISTS v_c AS SELECT 1", nil, function() return "c" end))

    local vs = host:get_analyze_queries()
    if #vs ~= 3 then err("expected 3 verification views, got " .. #vs) end
    if vs[1].policy_key ~= "pk_a" or vs[2].policy_key ~= "pk_b" or vs[3].policy_key ~= "pk_c" then
        err("verification view insertion order not preserved")
    end
    if type(vs[1].message) ~= "function" or vs[1].message() ~= "a" then
        err("message hook not carried onto the verification entry")
    end

    -- 2. override pk_b in place (later model wins, order preserved)
    host:register(vdesc("pk_b", "v_b2", "CREATE VIEW IF NOT EXISTS v_b2 AS SELECT 2", nil, function() return "b2" end))
    vs = host:get_analyze_queries()
    if #vs ~= 3 then err("override must not change count, got " .. #vs) end
    if vs[2].policy_key ~= "pk_b" or vs[2].view ~= "v_b2" then
        err("override must replace in place keeping order (got view " .. tostring(vs[2].view) .. ")")
    end

    -- 3. disabled removes the existing entry
    host:register(vdesc("pk_a", nil, nil, true, nil))
    vs = host:get_analyze_queries()
    if #vs ~= 2 then err("disabled should remove pk_a, got " .. #vs .. " entries") end
    if vs[1].policy_key ~= "pk_b" or vs[2].policy_key ~= "pk_c" then
        err("disabled removal must preserve remaining order")
    end

    -- 4. create_analyze_queries execs each entry's SQL
    host:create_analyze_queries(mock)
    local found_b2 = false
    for _, s in ipairs(exec_sqls) do
        if tostring(s):find("v_b2", 1, true) then found_b2 = true end
    end
    if not found_b2 then err("create_analyze_queries did not exec the v_b2 SQL") end

    -- 5. a non-message hook on the verification kind errors loudly
    if pcall(function()
        host:register{ kind = "analyze", schema = { id = "pk_x", policy_key = "pk_x" },
            hooks = { render = function() end } }
    end) then
        err("render hook on verification kind should error")
    end

    if #errors > 0 then
        return false, "Verification descriptor validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
