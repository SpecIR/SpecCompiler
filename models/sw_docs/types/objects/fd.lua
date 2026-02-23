---Functional Description (FD) type module.
---Design element that realizes Software Functions.

local M = {}
local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "FD",
    long_name = "Functional Description",
    description = "Description of a function or algorithm with traceability to requirements",
    extends = "TRACEABLE",
    pid_prefix = "FD",
    pid_format = "%s-%03d",
    attributes = {
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved", "Implemented" } },
        { name = "traceability", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("fd_handler")

return M
