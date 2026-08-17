---Traces To relation module for SpecCompiler.

return {
    kind = "relation",
    schema = {
        id = "TRACES_TO",
        extends = "PID_REF",
        long_name = "Traces To",
        description = "Traceability link from one object to another",
        source_attribute = "traceability",
        target_type_ref = "TRACEABLE",
    },
}
