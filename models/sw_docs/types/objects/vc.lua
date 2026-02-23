---Verification Case (VC) type module.

local M = {}

local spec_object_base = require("pipeline.shared.spec_object_base")

M.object = {
    id = "VC",
    long_name = "Verification Case",
    description = "Test specification for verifying requirements",
    extends = "TRACEABLE",
    pid_prefix = "VC",
    pid_format = "%s-%03d",
    attributes = {
        { name = "objective", type = "XHTML", min_occurs = 1 },
        { name = "verification_method", type = "ENUM", values = { "Test", "Analysis", "Inspection", "Demonstration" }, min_occurs = 1 },
        { name = "approach", type = "XHTML" },
        { name = "preconditions", type = "XHTML" },
        { name = "expected_results", type = "XHTML" },
        { name = "pass_criteria", type = "XHTML" },
        { name = "status", type = "ENUM", values = { "Draft", "Approved", "Passed", "Failed" } },
        { name = "traceability", type = "XHTML" },
    }
}

M.handler = spec_object_base.create_handler("vc_handler", {
    -- attr_order controls display sequence; unlisted attrs (approach, traceability) append alphabetically after status
    attr_order = {
        "objective",
        "verification_method",
        "preconditions",
        "expected_results",
        "pass_criteria",
        "status"
    },
})

return M
