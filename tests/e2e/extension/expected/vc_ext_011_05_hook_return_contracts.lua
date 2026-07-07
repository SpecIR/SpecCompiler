-- Test oracle for VC-EXT-011 (case 05): typed hook return contracts.
--
-- HOST-REGISTRY CONTRACT TEST -- builds a host with a mock data manager and
-- verifies the dispatch-time return-type postcondition the host wraps around
-- every indexed hook:
--   * a hook honoring its contract passes its value through unchanged,
--   * a wrong-typed return errors loudly, naming kind/id/hook,
--   * nil is accepted ("nothing produced") unless the contract requires a
--     value (verification `message`).

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

    -- A well-behaved hook: value passes through unchanged.
    host:register{
        kind = "object",
        schema = { id = "RC_GOOD" },
        hooks = { render = function() return { "block" } end },
    }
    local good = host:get_hook("object", "RC_GOOD", "render")
    local ok_good, res = pcall(good, {})
    if not ok_good then
        err("conforming render must not error: " .. tostring(res))
    elseif type(res) ~= "table" or res[1] ~= "block" then
        err("conforming render's value must pass through unchanged")
    end

    -- nil stays an accepted return (means "nothing produced / fall back").
    host:register{
        kind = "object",
        schema = { id = "RC_NIL" },
        hooks = { render = function() return nil end },
    }
    local ok_nil = pcall(host:get_hook("object", "RC_NIL", "render"), {})
    if not ok_nil then
        err("nil return must stay accepted for non-required hooks")
    end

    -- An "ast" hook returning a string must fail loudly, naming the hook.
    host:register{
        kind = "object",
        schema = { id = "RC_BAD_AST" },
        hooks = { render = function() return "<w:p>raw ooxml</w:p>" end },
    }
    local ok_bad, bad_err = pcall(host:get_hook("object", "RC_BAD_AST", "render"), {})
    if ok_bad then
        err("render returning a string must error")
    elseif not tostring(bad_err):find("RC_BAD_AST", 1, true)
        or not tostring(bad_err):find("render", 1, true) then
        err("wrong-return error must name kind/id/hook: " .. tostring(bad_err))
    end

    -- render_link is a "display" hook: a string OR a display table is
    -- accepted; anything else (e.g. a number) must fail loudly.
    host:register{
        kind = "relation",
        schema = { id = "RC_DISPLAY_LINK", extends = "PID_REF" },
        hooks = { render_link = function() return { text = "Seção 3", suppress_spec_prefix = true } end },
    }
    local ok_disp, disp = pcall(host:get_hook("relation", "RC_DISPLAY_LINK", "render_link"), {})
    if not ok_disp then
        err("render_link returning a display table must be accepted: " .. tostring(disp))
    elseif type(disp) ~= "table" or disp.text ~= "Seção 3" then
        err("render_link display table must pass through unchanged")
    end

    host:register{
        kind = "relation",
        schema = { id = "RC_BAD_LINK", extends = "PID_REF" },
        hooks = { render_link = function() return 42 end },
    }
    local ok_link, link_err = pcall(host:get_hook("relation", "RC_BAD_LINK", "render_link"), {})
    if ok_link then
        err("render_link returning a number must error")
    elseif not tostring(link_err):find("RC_BAD_LINK", 1, true) then
        err("render_link error must name the type: " .. tostring(link_err))
    end

    -- verification `message` is REQUIRED: returning nil must error.
    host:register{
        kind = "analyze",
        schema = { id = "rc_check", view = "view_rc_check", policy_key = "rc_check", sql = "SELECT 1" },
        hooks = { message = function() return nil end },
    }
    local ok_msg, msg_err = pcall(host:get_hook("analyze", "rc_check", "message"), {})
    if ok_msg then
        err("message returning nil must error (required return)")
    elseif not tostring(msg_err):find("must return a string", 1, true) then
        err("message error must state the required type: " .. tostring(msg_err))
    end

    if #errors > 0 then
        return false, "Hook return contract validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true
end
