---Low-Level Requirement (LLR) type module.

return {
    kind = "object",
    schema = {
        id = "LLR",
        long_name = "Low-Level Requirement",
        description = "Detailed implementation requirement derived from HLR",
        extends = "TRACEABLE",
        pid_prefix = "LLR",
        pid_format = "%s-%03d",
        attributes = {
            { name = "rationale", type = "XHTML" },
            { name = "verification_method", type = "ENUM", values = { "Test", "Analysis", "Inspection", "Demonstration" } },
            { name = "traceability", type = "XHTML" },
        }
    },
}
