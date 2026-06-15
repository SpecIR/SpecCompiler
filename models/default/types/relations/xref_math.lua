---Cross-reference relation type for math equations.
---Targets: MATH float type.
---
---@module xref_math

return {
    kind = "relation",
    schema = {
        id = "XREF_MATH",
        extends = "LABEL_REF",
        long_name = "Math Reference",
        description = "Cross-reference to a mathematical equation",
        target_type_ref = "MATH",
    },
}
