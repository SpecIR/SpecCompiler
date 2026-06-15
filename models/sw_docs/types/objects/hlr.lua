---High-Level Requirement (HLR) type module.

return {
    kind = "object",
    schema = {
        id = "HLR",
        long_name = "High-Level Requirement",
        description = "A top-level system requirement",
        extends = "TRACEABLE",
        pid_prefix = "HLR",
        pid_format = "%s-%03d",
        attributes = {
            { name = "priority", type = "ENUM", values = { "High", "Mid", "Low" } },
            { name = "rationale", type = "XHTML" },
        }
    },
}
