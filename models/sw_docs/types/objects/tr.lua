---Test Result (TR) type module.
---Records the outcome of executing a verification case.

local M = {}

local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "TR",
    long_name = "Test Result",
    description = "Record of test execution result for a verification case",
    extends = "TRACEABLE",
    pid_prefix = "TR",
    pid_format = "%s-%03d",
    attributes = {
        { name = "result", type = "ENUM", values = { "Pass", "Fail", "Blocked", "Not Run" }, min_occurs = 1 },
        { name = "execution_date", type = "STRING" },
        { name = "executed_by", type = "STRING" },
        { name = "test_file", type = "STRING" },
        { name = "duration_ms", type = "STRING" },
        { name = "failure_reason", type = "XHTML" },
        { name = "traceability", type = "XHTML", min_occurs = 1 },  -- Link to VC
        { name = "notes", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("tr_handler")

return M
