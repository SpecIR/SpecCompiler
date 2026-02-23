---Test Results Report type module for SpecCompiler.
---Aggregates test results from VC execution.

local specification_base = require("pipeline.shared.specification_base")

local M = {}

M.specification = {
    id = "TRR",
    long_name = "Test Results Report",
    description = "Test execution results document",
    extends = "SPEC",
    attributes = {
        { name = "version", type = "STRING", min_occurs = 0 },
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
        { name = "date", type = "DATE" },
        { name = "test_run_id", type = "STRING" },
        { name = "environment", type = "STRING" },
    }
}

M.handler = specification_base.create_handler("trr_handler", {
    show_pid = false,
    style = "Title"
})

return M
