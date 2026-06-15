---REALIZES relation module for SpecCompiler.
---FD realizes SF requirements through design implementation.

return {
    kind = "relation",
    schema = {
        id = "REALIZES",
        extends = "PID_REF",
        long_name = "Realizes",
        description = "Design element realizes functional requirements",
        source_attribute = "traceability",
        source_type_ref = "FD",
        target_type_ref = "SF",
    },
}
