---Software Requirements Specification type module for SpecCompiler.

return {
    kind = "specification",
    schema = {
        id = "SRS",
        long_name = "Software Requirements Specification",
        description = "Requirements specification document",
        extends = "SPEC_TITLE",
        show_pid = false,    -- Just show title, not "SRS-001: Title"
        style = "Title",
        -- Attributes
        attributes = {
            { name = "version", type = "STRING" },
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
            { name = "date", type = "DATE" },
        }
    },
}
