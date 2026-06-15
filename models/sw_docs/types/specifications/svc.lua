---Software Verification Cases type module for SpecCompiler.

return {
    kind = "specification",
    schema = {
        id = "SVC",
        long_name = "Software Verification Cases",
        description = "Verification cases document",
        extends = "SPEC_TITLE",
        show_pid = false,
        style = "Title",
        attributes = {
            { name = "version", type = "STRING", min_occurs = 0 },
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved" }, min_occurs = 0 },
            { name = "date", type = "DATE" },
        }
    },
}
