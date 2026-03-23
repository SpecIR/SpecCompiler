### DIC: Specification @SpecIR-01

A **Specification** is the root document container created from an H1 header. It represents a complete document like an SRS, SDD, or SVC. Each specification has a type, optional PID, and contains attributes and all spec objects within that document.

> description:
>
> **Formal definition:** `$: S = (tau, n, "pid", cc A, cc O)` --- a tuple of type, title, project identifier, attributes, and child objects.
>
> **Syntax:** `# [TypeRef:] Text [@PID]`
>
> **Full specification:** See the CommonSpec Language Specification for the complete grammar, type inference rules, and examples.
