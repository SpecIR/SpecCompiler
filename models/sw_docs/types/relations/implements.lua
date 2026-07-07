---Implementation relation: a software unit implements code symbols.
---Source: CSU objects (via the `implements` attribute).
---Target: SYMBOL objects extracted from source-code analysis.
---
---@module implements

return {
    kind = "relation",
    schema = {
        id = "IMPLEMENTS",
        extends = "PID_REF",
        long_name = "Implements",
        description = "Software unit implements a code symbol",
        source_attribute = "implements",
        source_type_ref = "CSU",
        target_type_ref = "SYMBOL",
    },
    hooks = {},
}
