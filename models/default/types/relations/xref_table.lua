---Cross-reference relation type for tables.
---Targets: TABLE float type.
---
---@module xref_table

return {
    kind = "relation",
    schema = {
        id = "XREF_TABLE",
        extends = "LABEL_REF",
        long_name = "Table Reference",
        description = "Cross-reference to a table",
        target_type_ref = "TABLE",
    },
}
