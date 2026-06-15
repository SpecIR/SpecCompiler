---Test Results Report type module for SpecCompiler.
---Aggregates test results from VC execution.

return {
    kind = "specification",
    schema = {
        id = "TRR",
        long_name = "Test Results Report",
        description = "Test execution results document",
        extends = "SPEC_TITLE",
        show_pid = false,
        style = "Title",
        attributes = {
            { name = "version", type = "STRING", min_occurs = 0 },
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
            { name = "date", type = "DATE" },
            { name = "test_run_id", type = "STRING" },
            { name = "environment", type = "STRING" },
        }
    },
}
