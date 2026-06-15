-- Test oracle for VC-EXT-009: Canonical ctx + ctx:require (HLR-EXT-009)
--
-- Exercises the contract.ctx module in isolation (the per-call render hooks --
-- object/spec/float/view render, relation render_link, verification message --
-- consume it in production):
--   1. a full invariant core builds and is readable
--   2. ctx:require returns present fields, errors loudly (naming the field)
--      on nil
--   3. the ctx is frozen -- any assignment errors
--   4. subject is polymorphic -- absent members read as nil without error
--   5. a missing invariant-core field is a loud build error naming the field
--   6. subject defaults to a table when omitted

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local ctxmod = require("contract.ctx")

    local function make_fields()
        return {
            data = { _db = true },
            pandoc = pandoc,
            log = { info = function() end },
            diagnostics = { add = function() end },
            format = "json",
            spec_id = "SPEC-CTX-001",
            model = "default",
            config = { build_dir = "build" },
            subject = { object = { id = "OBJ-1" } },
            capability = "render",
        }
    end

    -- 1. Valid build succeeds
    local ok, ctx = pcall(ctxmod.new, make_fields())
    if not ok then
        err("ctx.new with full core failed: " .. tostring(ctx))
        return false, "Canonical ctx validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end

    -- 2. require returns invariant fields; read passthrough works
    if ctx:require("model") ~= "default" then err("require('model') wrong") end
    if ctx:require("format") ~= "json" then err("require('format') wrong") end
    if type(ctx:require("subject")) ~= "table" then err("require('subject') not a table") end
    if ctx.spec_id ~= "SPEC-CTX-001" then err("read spec_id wrong: " .. tostring(ctx.spec_id)) end
    if ctx.capability ~= "render" then err("read capability wrong") end
    if ctx.subject.object.id ~= "OBJ-1" then err("subject.object passthrough wrong") end

    -- 2b. require on a nil field errors loudly and names the field
    local rok, rerr = pcall(function() return ctx:require("does_not_exist") end)
    if rok then
        err("require('does_not_exist') should have errored")
    elseif not tostring(rerr):find("does_not_exist", 1, true) then
        err("require error should name the field, got: " .. tostring(rerr))
    end

    -- 3. frozen: assigning any field errors (new or existing key name)
    if pcall(function() ctx.newfield = 1 end) then
        err("assigning ctx.newfield should error (frozen)")
    end
    if pcall(function() ctx.model = "mutated" end) then
        err("assigning existing ctx.model should error (frozen)")
    end

    -- 4. polymorphic subject: absent member reads as nil without error
    local pok = pcall(function() return ctx.subject.float end)
    if not pok then err("reading absent subject.float should not error") end
    if ctx.subject.float ~= nil then err("absent subject.float should be nil") end

    -- 5. missing invariant-core field => loud build error naming the field
    local core = { "data", "pandoc", "log", "diagnostics", "format", "spec_id", "model", "config" }
    for _, drop in ipairs(core) do
        local f = make_fields()
        f[drop] = nil
        local bok, berr = pcall(ctxmod.new, f)
        if bok then
            err("ctx.new should fail when '" .. drop .. "' is missing")
        elseif not tostring(berr):find(drop, 1, true) then
            err("build error should name missing field '" .. drop
                .. "', got: " .. tostring(berr))
        end
    end

    -- 6. subject defaults to a table when omitted
    local f2 = make_fields()
    f2.subject = nil
    local sok, ctx2 = pcall(ctxmod.new, f2)
    if not sok then
        err("ctx.new without subject should succeed (defaults to {})")
    elseif type(ctx2.subject) ~= "table" then
        err("omitted subject should default to a table")
    end

    if #errors > 0 then
        return false, "Canonical ctx validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
