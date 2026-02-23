---Low-Level Requirement (LLR) type module.

local M = {}
local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "LLR",
    long_name = "Low-Level Requirement",
    description = "Detailed implementation requirement derived from HLR",
    extends = "TRACEABLE",
    pid_prefix = "LLR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "rationale", type = "XHTML" },
        { name = "verification_method", type = "ENUM", values = { "Test", "Analysis", "Inspection", "Demonstration" } },
        { name = "traceability", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("llr_handler")

return M
