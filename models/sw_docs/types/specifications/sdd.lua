---Software Design Description type module for SpecCompiler.

return {
    kind = "specification",
    schema = {
        id = "SDD",
        long_name = "Software Design Description",
        description = "Design description document",
        extends = "SPEC_TITLE",
        show_pid = false,
        style = "Title",
        attributes = {
            { name = "version", type = "STRING", min_occurs = 0 },
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" } },
            { name = "date", type = "DATE" },
        }
    },
}
