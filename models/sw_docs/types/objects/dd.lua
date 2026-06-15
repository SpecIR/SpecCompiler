---Design Decision (DD) type module.

return {
    kind = "object",
    schema = {
        id = "DD",
        long_name = "Design Decision",
        description = "Architectural or design decision with rationale",
        extends = "TRACEABLE",
        pid_prefix = "DD",
        pid_format = "%s-%03d",
        attributes = {
            { name = "rationale", type = "XHTML", min_occurs = 1 },
        }
    },
}
