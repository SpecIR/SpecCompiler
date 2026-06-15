---Functional Description (FD) type module.
---Design element that realizes Software Functions.

return {
    kind = "object",
    schema = {
        id = "FD",
        long_name = "Functional Description",
        description = "Description of a function or algorithm with traceability to requirements",
        extends = "TRACEABLE",
        pid_prefix = "FD",
        pid_format = "%s-%03d",
        attributes = {
            { name = "status", type = "ENUM", values = { "Draft", "Review", "Approved", "Implemented", "Deprecated", "Retired" } },
            { name = "traceability", type = "XHTML" },
        }
    },
}
