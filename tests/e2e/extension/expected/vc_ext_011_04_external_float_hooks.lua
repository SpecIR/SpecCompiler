-- Test oracle for VC-EXT-011 (case 04): host external-float-hook contract (step 11)
--
-- HOST-REGISTRY CONTRACT TEST -- builds a host with a mock data manager and
-- asserts on the external-float hook INDEX and the register-time mutual-
-- exclusion rule. It does NOT render or inspect actual_doc; end-to-end external
-- rendering is covered by the floats suite (vc_024_01/02), toolchain-gated.
--
-- External floats (e.g. PLANTUML) expose prepare_task/handle_result indexed by
-- the host -- no require-time register_renderer side effect. A float renders
-- internally (render) XOR externally (prepare_task/handle_result), never both.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local registry = require("contract.registry")
    local mock = {
        execute = function() end,
        query_all = function() return {} end,
        query_one = function() return nil end,
        register_resolver = function() end,
        db = { exec_sql = function() end },
    }
    local host = registry.new{ data = mock }
    host:load_model("default")

    -- PLANTUML renders externally: prepare_task + handle_result, NO render hook.
    if type(host:get_hook("float", "PLANTUML", "prepare_task")) ~= "function" then
        err("PLANTUML should expose a prepare_task hook")
    end
    if type(host:get_hook("float", "PLANTUML", "handle_result")) ~= "function" then
        err("PLANTUML should expose a handle_result hook")
    end
    if host:get_hook("float", "PLANTUML", "render") ~= nil then
        err("PLANTUML is external-only and must NOT have an internal render hook")
    end

    -- (CHART is abnt-model-owned; its hook contract is covered by the abnt suite.)

    -- Mutual exclusion: a float may not declare BOTH render and external hooks.
    local ok, e = pcall(function()
        host:register{
            kind = "float",
            schema = { id = "BOGUSFLOAT" },
            hooks = { render = function() end, prepare_task = function() end },
        }
    end)
    if ok then
        err("a float declaring both render and prepare_task should error")
    elseif not tostring(e):find("both", 1, true) then
        err("mutual-exclusion error should explain the conflict: " .. tostring(e))
    end

    if #errors > 0 then
        return false, "External float hooks validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
