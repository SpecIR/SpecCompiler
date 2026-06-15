---References object type for the default model.
---An unnumbered section for bibliography / references.
---
---Usage:
---  ## REFERENCES: References
---  Bibliography entries follow...

return {
    kind = "object",
    schema = {
        id = "REFERENCES",
        long_name = "References",
        description = "Bibliography / references section",
        is_composite = true,
        numbered = false,
        implicit_aliases = { "references", "bibliography", "works cited" },
        unnumbered = true,
        skip_attributes = true,
    },
}
