---Software Function (SF) type module.
---Groups related high-level requirements into functional units.

local M = {}

local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "SF",
    long_name = "Software Function",
    description = "Functional grouping of related high-level requirements",
    extends = "TRACEABLE",
    pid_prefix = "SF",
    pid_format = "%s-%03d",
    attributes = {
        { name = "description", type = "XHTML" },
        { name = "rationale", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("sf_handler")

return M
