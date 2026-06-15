---Software User Manual specification type module for SpecCompiler.

return {
    kind = "specification",
    schema = {
        id = "SUM",
        long_name = "Software User Manual",
        description = "User manual and operational guidance document",
        extends = "SPEC_TITLE",
        show_pid = false,    -- Just show title, not "SUM-001: Title"
        style = "Title",
        -- Attributes
        attributes = {
            { name = "version", type = "STRING", min_occurs = 0 },
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
            { name = "date", type = "DATE" },
        }
    },
}
