---TRACEABLE base type module.
---Base schema + the standard requirement-card render for all traceable objects.
---Leaf types (HLR, LLR, DD, ...) extend this and inherit the card render via the
---host's extends-chain dispatch; they declare any render options (attr_order,
---show_pid, ...) as plain schema fields. A type wanting a custom render declares
---its own hooks.render (e.g. COVER).
---
---@module traceable
local spec_object_base = require("pipeline.shared.spec_object_base")

return {
    kind = "object",
    schema = {
        id = "TRACEABLE",
        long_name = "Traceable Object",
        description = "Base type for objects with PIDs and traceability",
        extends = "SECTION",
        -- Common attributes inherited by all traceable types
        attributes = {
            { name = "status", type = "ENUM",
              values = { "Draft", "Review", "Approved",
                         "Implemented", "Deprecated", "Retired" } },
            -- Universal traceability links: > traceability: [PID](@)
            { name = "traceability", type = "XHTML" },
        }
    },
    -- The standard requirement-card render, inherited by every leaf type that
    -- extends TRACEABLE (host get_hook_inherited).
    hooks = { render = spec_object_base.card_render },
}
