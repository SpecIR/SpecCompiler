---High-Level Requirement (HLR) type module.

local M = {}
local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    description = "A top-level system requirement",
    extends = "TRACEABLE",
    pid_prefix = "HLR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "priority", type = "ENUM", values = { "High", "Mid", "Low" } },
        { name = "rationale", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("hlr_handler")

return M
