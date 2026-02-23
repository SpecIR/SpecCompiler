---Software Design Description type module for SpecCompiler.

local specification_base = require("pipeline.shared.specification_base")

local M = {}

M.specification = {
    id = "SDD",
    long_name = "Software Design Description",
    description = "Design description document",
    extends = "SPEC",
    attributes = {
        { name = "version", type = "STRING", min_occurs = 0 },
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
        { name = "date", type = "DATE" },
    }
}

M.handler = specification_base.create_handler("sdd_handler", {
    show_pid = false,
    style = "Title"
})

return M
