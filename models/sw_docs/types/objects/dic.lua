---Dictionary (DIC) type module.
---Defines terms and definitions used throughout the documentation.

return {
    kind = "object",
    schema = {
        id = "DIC",
        long_name = "Dictionary Entry",
        description = "A term definition in the project dictionary",
        extends = "TRACEABLE",
        pid_prefix = "DIC",
        pid_format = "%s-%03d",
        attributes = {
            { name = "term", type = "STRING" },
            { name = "acronym", type = "STRING" },
            { name = "domain", type = "STRING" },
            { name = "description", type = "XHTML" },
            { name = "traceability", type = "XHTML" },
        }
    },
}
