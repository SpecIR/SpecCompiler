---VERIFIES relation module for SpecCompiler.
---VC verifies HLR or LLR through the traceability attribute.

return {
    kind = "relation",
    schema = {
        id = "VERIFIES",
        extends = "PID_REF",
        long_name = "Verifies",
        description = "Verification case covers a requirement (HLR or LLR)",
        source_attribute = "traceability",
        source_type_ref = "VC",
        target_type_ref = "HLR,LLR",
    },
}
