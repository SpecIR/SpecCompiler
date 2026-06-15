---Computer Software Unit (CSU) type module.
---MIL-STD-498 decomposition level for source files/units.

return {
    kind = "object",
    schema = {
        id = "CSU",
        long_name = "Computer Software Unit",
        description = "Implementation unit in MIL-STD-498 decomposition",
        extends = "TRACEABLE",
        pid_prefix = "CSU",
        pid_format = "%s-%03d",
        attributes = {
            { name = "file_path", type = "STRING", min_occurs = 1 },
            { name = "language", type = "STRING" },
            { name = "description", type = "XHTML" },
            { name = "traceability", type = "XHTML" },
        }
    },
}
