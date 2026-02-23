---Design Decision (DD) type module.

local M = {}

local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "DD",
    long_name = "Design Decision",
    description = "Architectural or design decision with rationale",
    extends = "TRACEABLE",
    pid_prefix = "DD",
    pid_format = "%s-%03d",
    attributes = {
        { name = "rationale", type = "XHTML", min_occurs = 1 },
    }
}

M.handler = spec_object_base.create_handler("dd_handler")

return M
