---Default specification type for SpecCompiler.
---Used when no explicit specification type is provided in H1 headers.
---
---@module spec
local M = {}

M.specification = {
    id = "SPEC",
    long_name = "Specification",
    description = "Default specification type for documents",
    is_default = true,  -- Default type for H1 headers without explicit TYPE: prefix
    attributes = {
        { name = "version", type = "STRING" },
        { name = "document_id", type = "STRING" },
        { name = "classification", type = "STRING" },
        { name = "revision", type = "STRING" },
        { name = "approver", type = "STRING" },
        { name = "build_number", type = "INTEGER" },
        { name = "progress", type = "REAL" },
        { name = "is_stable", type = "BOOLEAN" },
        { name = "release_date", type = "DATE" },
        { name = "stage", type = "ENUM", values = { "Alpha", "Beta" } },
        { name = "notes", type = "XHTML" },
    }
}

return M
