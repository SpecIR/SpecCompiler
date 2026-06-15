-- Test oracle for VC-EXT-011 (case 03): host float-hook INDEX contract (step 10)
--
-- HOST-REGISTRY CONTRACT TEST -- builds a host with a mock data manager and
-- asserts on the float hook INDEX only. It does NOT render or inspect
-- actual_doc; end-to-end float rendering (real syntax -> output) is covered by
-- the floats suite (vc_014_*, vc_024_*, vc_032_*).
--
-- The host indexes internal float render hooks. Crucially it distinguishes:
--   * registered + has render hook (TABLE/MATH/LISTING -> on_render_CodeBlock)
--   * registered but NO render hook (FIGURE renders via the image fallback)
--   * not registered at all
-- get_hook returns nil for the latter two; get_descriptor disambiguates them.

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

    -- TABLE renders via on_render_CodeBlock -> indexed render hook.
    if type(host:get_hook("float", "TABLE", "render")) ~= "function" then
        err("expected a render hook for float/TABLE")
    end

    -- FIGURE is registered (descriptor present) but renders via on_transform /
    -- the image fallback, so it has NO render hook. This is the distinction the
    -- plan calls out: nil render hook != not registered.
    if host:get_hook("float", "FIGURE", "render") ~= nil then
        err("FIGURE should have no render hook (renders via image fallback)")
    end
    if host:get_descriptor("float", "FIGURE") == nil then
        err("FIGURE should still be REGISTERED (descriptor present)")
    end

    -- An unregistered type has neither a hook nor a descriptor.
    if host:get_hook("float", "NOSUCHFLOAT", "render") ~= nil then
        err("unregistered float should have no render hook")
    end
    if host:get_descriptor("float", "NOSUCHFLOAT") ~= nil then
        err("unregistered float should have no descriptor")
    end

    if #errors > 0 then
        return false, "Float render index validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
