---Computer Software Component (CSC) type module.
---MIL-STD-498 decomposition level for folders/subsystems/layers.

return {
    kind = "object",
    schema = {
        id = "CSC",
        long_name = "Computer Software Component",
        description = "Architectural component in MIL-STD-498 decomposition",
        extends = "TRACEABLE",
        pid_prefix = "CSC",
        pid_format = "%s-%03d",
        attributes = {
            { name = "component_type", type = "ENUM", values = { "Layer", "Subsystem", "Package", "Service", "Infrastructure", "Model" }, min_occurs = 1 },
            { name = "path", type = "STRING", min_occurs = 1 },
            { name = "description", type = "XHTML" },
            { name = "traceability", type = "XHTML" },
        }
    },
}
