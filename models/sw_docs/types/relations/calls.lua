---Call relation between code symbols, extracted from static analysis.
---Source: SYMBOL objects (via the `calls` attribute).
---Target: SYMBOL objects defined in the same project.
---
---@module calls

return {
    kind = "relation",
    schema = {
        id = "CALLS",
        extends = "PID_REF",
        long_name = "Calls",
        description = "Code symbol calls another code symbol",
        source_attribute = "calls",
        source_type_ref = "SYMBOL",
        target_type_ref = "SYMBOL",
    },
    hooks = {},
}
