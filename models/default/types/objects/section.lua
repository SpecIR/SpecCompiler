---@diagnostic disable: lowercase-global

local M = {}

M.object = {
    id = "SECTION",
    long_name = "Section",
    description = "Standard document section",
    is_default = true,  -- Default type for headers without explicit TYPE: prefix
    is_composite = true,  -- Container type for hierarchical PID generation
    numbered = true,
    style_id = "SECTION",
    attributes = {
        -- Sections have optional description (rich text)
        { name = "description", type = "XHTML" },
    }
}

return M
