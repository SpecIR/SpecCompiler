-- Test oracle for VC-EXT-013 (case 01): pid_scheme registration contract.
--
-- Object types declare pid_scheme = "sequential" | "hierarchical". The
-- hierarchical scheme maps onto the legacy is_composite storage flag (kept as
-- a deprecated alias). Invalid values and conflicting legacy declarations are
-- loud register-time errors.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local registry = require("contract.registry")
    local Queries = require("db.queries")

    local captured = {}
    local mock = {
        execute = function(_, sql, params)
            if sql == Queries.types.insert_object_type then
                captured[params.identifier] = params
            end
        end,
        query_all = function() return {} end,
        query_one = function() return nil end,
        register_resolver = function() end,
        db = { exec_sql = function() end },
    }

    local host = registry.new{ data = mock }

    -- pid_scheme = "hierarchical" maps to is_composite = 1
    host:register{ kind = "object", schema = {
        id = "CH_HIER", pid_scheme = "hierarchical", pid_prefix = "ch" } }
    if not captured.CH_HIER then
        err("CH_HIER was not inserted")
    elseif captured.CH_HIER.is_composite ~= 1 then
        err("pid_scheme='hierarchical' must store is_composite=1, got "
            .. tostring(captured.CH_HIER.is_composite))
    end

    -- pid_scheme = "sequential" maps to is_composite = 0
    host:register{ kind = "object", schema = {
        id = "SEQ_PLAIN", pid_scheme = "sequential" } }
    if not captured.SEQ_PLAIN then
        err("SEQ_PLAIN was not inserted")
    elseif captured.SEQ_PLAIN.is_composite ~= 0 then
        err("pid_scheme='sequential' must store is_composite=0, got "
            .. tostring(captured.SEQ_PLAIN.is_composite))
    end

    -- legacy is_composite alias still accepted
    host:register{ kind = "object", schema = {
        id = "LEGACY_COMP", is_composite = true } }
    if not captured.LEGACY_COMP then
        err("LEGACY_COMP was not inserted")
    elseif captured.LEGACY_COMP.is_composite ~= 1 then
        err("legacy is_composite=true must still store is_composite=1, got "
            .. tostring(captured.LEGACY_COMP.is_composite))
    end

    -- invalid scheme value is a loud register-time error
    local ok, msg = pcall(function()
        host:register{ kind = "object", schema = {
            id = "BAD_SCHEME", pid_scheme = "chapters" } }
    end)
    if ok then
        err("pid_scheme='chapters' must be a register-time error")
    elseif not tostring(msg):find("pid_scheme", 1, true) then
        err("invalid-scheme error must name pid_scheme, got: " .. tostring(msg))
    end

    -- scheme conflicting with the legacy flag is a loud register-time error
    local ok2, msg2 = pcall(function()
        host:register{ kind = "object", schema = {
            id = "CONFLICT", pid_scheme = "sequential", is_composite = true } }
    end)
    if ok2 then
        err("pid_scheme='sequential' + is_composite=true must be a register-time error")
    elseif not tostring(msg2):find("pid_scheme", 1, true) then
        err("conflict error must name pid_scheme, got: " .. tostring(msg2))
    end

    if #errors > 0 then
        return false, "pid_scheme validation:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
