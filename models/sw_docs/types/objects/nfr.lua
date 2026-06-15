---Non-Functional Requirement (NFR) type module.
---Captures performance, security, reliability, and other quality attribute requirements.

return {
    kind = "object",
    schema = {
        id = "NFR",
        long_name = "Non-Functional Requirement",
        description = "Performance, security, reliability, or other quality attribute requirement",
        extends = "TRACEABLE",
        pid_prefix = "NFR",
        pid_format = "%s-%03d",
        attributes = {
            { name = "category", type = "ENUM", values = { "Performance", "Security", "Reliability", "Usability", "Maintainability", "Scalability" } },
            { name = "priority", type = "ENUM", values = { "High", "Mid", "Low" } },
            { name = "metric", type = "STRING" },
            { name = "rationale", type = "XHTML" },
        }
    },
}
