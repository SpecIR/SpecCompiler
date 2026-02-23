---TRACEABLE base type module.
---Base schema for all traceable specification objects.
---
---Types like HLR, LLR, DD, etc. extend this type to inherit
---common attributes and rendering behavior.
---
---@module traceable
local M = {}

M.object = {
    id = "TRACEABLE",
    long_name = "Traceable Object",
    description = "Base type for objects with PIDs and traceability",
    extends = "SECTION",
    -- Common attributes inherited by all traceable types
    attributes = {
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved", "Implemented" } },
    }
}

-- No handler needed for base type - child types use spec_object_base.create_handler()
M.handler = {
    name = "traceable_handler",
    prerequisites = {},
}

return M
