---Software Function (SF) type module.
---Groups related high-level requirements into functional units.

return {
    kind = "object",
    schema = {
        id = "SF",
        long_name = "Software Function",
        description = "Functional grouping of related high-level requirements",
        extends = "TRACEABLE",
        pid_prefix = "SF",
        pid_format = "%s-%03d",
        attributes = {
            { name = "description", type = "XHTML" },
            { name = "rationale", type = "XHTML" },
        }
    },
}
