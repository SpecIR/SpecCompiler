-- Test oracle for VC-EXT-014 (case 01): dangling extends target.
--
-- host:finalize() must reject a type whose `extends` names a type that was
-- never registered (for any kind), naming kind, child, and missing parent.
-- Legitimate chains -- including cross-model ones resolved only at finalize
-- time -- must keep passing.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local registry = require("contract.registry")

    local function make_mock()
        return {
            execute = function() end,
            query_all = function() return {} end,
            query_one = function() return nil end,
            register_resolver = function() end,
            db = { exec_sql = function() end },
        }
    end

    -- A dangling extends is a loud finalize-time error
    local host = registry.new{ data = make_mock() }
    host:register{ kind = "object", schema = { id = "ORPHAN", extends = "TEXTUAL" } }
    local ok, msg = pcall(function() host:finalize() end)
    if ok then
        err("finalize() must fail when extends names an unregistered type")
    else
        local m = tostring(msg)
        for _, needle in ipairs({ "object", "ORPHAN", "TEXTUAL" }) do
            if not m:find(needle, 1, true) then
                err("error must name '" .. needle .. "', got: " .. m)
            end
        end
    end

    -- A legitimate chain finalizes fine (real models, cross-model extends)
    local host2 = registry.new{ data = make_mock() }
    host2:load_model("default")
    host2:load_model("sw_docs")
    local ok2, msg2 = pcall(function() host2:finalize() end)
    if not ok2 then
        err("finalize() must accept valid chains, got: " .. tostring(msg2))
    end

    if #errors > 0 then
        return false, "dangling extends:\n  - " .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
