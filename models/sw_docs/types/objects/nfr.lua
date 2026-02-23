---Non-Functional Requirement (NFR) type module.
---Captures performance, security, reliability, and other quality attribute requirements.

local M = {}

local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "NFR",
    long_name = "Non-Functional Requirement",
    description = "Performance, security, reliability, or other quality attribute requirement",
    extends = "TRACEABLE",
    pid_prefix = "NFR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "category", type = "ENUM", values = { "Performance", "Security", "Reliability", "Usability", "Maintainability", "Scalability" } },
        { name = "priority", type = "ENUM", values = { "High", "Mid", "Low" } },
        { name = "metric", type = "STRING" },
        { name = "rationale", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("nfr_handler")

return M
