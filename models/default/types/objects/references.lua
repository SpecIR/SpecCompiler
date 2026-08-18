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
        pid_scheme = "hierarchical",
        pid_prefix = "ref",  -- own chain: MAN-ref1, not a slot in the sec chain
        numbered = false,
        implicit_aliases = { "references", "bibliography", "works cited" },
        unnumbered = true,
        skip_attributes = true,
    },
}
