---Software Requirements Specification type module for SpecCompiler.

local specification_base = require("pipeline.shared.specification_base")

local M = {}

M.specification = {
    id = "SRS",
    long_name = "Software Requirements Specification",
    description = "Requirements specification document",
    extends = "SPEC",
    -- Attributes
    attributes = {
        { name = "version", type = "STRING" },
        { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
        { name = "date", type = "DATE" },
    }
}

-- Handler for rendering specification title
-- Model controls the rendering, not the assembler
-- Title is rendered as a Div (not Header) so it doesn't affect section numbering
M.handler = specification_base.create_handler("srs_handler", {
    show_pid = false,    -- Just show title, not "SRS-001: Title"
    style = "Title"
})

return M
