---Software Verification Cases type module for SpecCompiler.

local specification_base = require("pipeline.shared.specification_base")

local M = {}

M.specification = {
    id = "SVC",
    long_name = "Software Verification Cases",
    description = "Verification cases document",
    extends = "SPEC",
    attributes = {
        { name = "version", type = "STRING", min_occurs = 0 },
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" }, min_occurs = 0 },
        { name = "date", type = "DATE" },
    }
}

M.handler = specification_base.create_handler("svc_handler", {
    show_pid = false,
    style = "Title"
})

return M
