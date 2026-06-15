---@diagnostic disable: lowercase-global

-- Collapsed Design-B descriptor (HLR-EXT-011): the module returns its descriptor
-- directly; the host reads kind/schema/hooks. SECTION is a pure schema type
-- (default + composite) with no custom render -- it uses the host default.
return {
    kind = "object",
    schema = {
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
        },
    },
}
