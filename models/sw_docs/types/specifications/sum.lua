---Software User Manual specification type module for SpecCompiler.

local specification_base = require("pipeline.shared.specification_base")

local M = {}

M.specification = {
    id = "SUM",
    long_name = "Software User Manual",
    description = "User manual and operational guidance document",
    extends = "SPEC",
    -- Attributes
    attributes = {
        { name = "version", type = "STRING", min_occurs = 0 },
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
        { name = "date", type = "DATE" },
    }
}

-- Handler for rendering specification title
-- Model controls the rendering, not the assembler
-- Title is rendered as a Div (not Header) so it doesn't affect section numbering
M.handler = specification_base.create_handler("sum_handler", {
    show_pid = false,    -- Just show title, not "SUM-001: Title"
    style = "Title"
})

return M
