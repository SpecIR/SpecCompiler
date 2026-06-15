-- Test oracle for VC-EXT-011 (case 02): inherited object card render
--
-- The standard object-card render lives ONCE on the base type TRACEABLE
-- (spec_object_base.card_render). Leaf requirement types (HLR, ...) are pure
-- schema and inherit it via the host's extends-chain dispatch
-- (get_hook_inherited). A type with a custom render (COVER) declares its own
-- hooks.render and is dispatched directly.

return function(actual_doc, helpers)  -- luacheck: ignore actual_doc helpers
    local errors = {}
    local function err(m) errors[#errors + 1] = m end

    local spec_object_base = require("pipeline.shared.spec_object_base")
    local registry = require("contract.registry")

    if type(spec_object_base.card_render) ~= "function" then
        err("spec_object_base.card_render must be the host card renderer")
    end

    local function make_mock()
        return {
            execute = function() end,
            query_all = function() return {} end,
            query_one = function() return nil end,
            register_resolver = function() end,
            db = { exec_sql = function() end },
        }
    end
    local host = registry.new{ data = make_mock() }
    host:load_model("default")   -- SECTION, COVER, ...
    host:load_model("sw_docs")   -- TRACEABLE, HLR, ...

    -- TRACEABLE (base) carries the one card render hook. The host wraps hooks
    -- with the return-contract check at registration, so compare identity via
    -- the index (not against the raw function).
    local traceable_render = host:get_hook("object", "TRACEABLE", "render")
    if type(traceable_render) ~= "function" then
        err("TRACEABLE must carry the card render hook")
    end

    -- HLR is PURE SCHEMA: no direct render, but inherits the card render via extends.
    if host:get_hook("object", "HLR", "render") ~= nil then
        err("HLR must NOT declare its own render (pure schema)")
    end
    if host:get_hook_inherited("object", "HLR", "render") ~= traceable_render then
        err("HLR must inherit the card render from TRACEABLE")
    end
    if host:extends_of("object", "HLR") ~= "TRACEABLE" then
        err("host did not capture HLR extends=TRACEABLE")
    end

    -- SECTION (composite container) carries NO card render up its chain.
    if host:get_hook_inherited("object", "SECTION", "render") ~= nil then
        err("SECTION must not render a card (it is the composite container)")
    end

    -- COVER is the custom-render escape hatch: its own hooks.render, not the card.
    local cover_render = host:get_hook("object", "COVER", "render")
    if type(cover_render) ~= "function" then
        err("COVER must declare its own custom render hook")
    end
    if cover_render == spec_object_base.card_render then
        err("COVER's render must be custom, not the shared card render")
    end

    if #errors > 0 then
        return false, "Inherited card-render validation failed:\n  - "
            .. table.concat(errors, "\n  - ")
    end
    return true, nil
end
