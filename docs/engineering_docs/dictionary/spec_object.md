### DIC: Spec Object @SpecIR-02

A **Spec Object** represents a traceable element in a specification document, created from H2-H6 headers. Objects can be requirements (HLR, LLR), verification cases (VC), design elements (FD, CSC, CSU), or structural sections (SECTION). Each object has a type, PID and can contain attributes, body content, floats, relations, views, and child objects.

> description:
>
> **Formal definition:** `$: O = (tau, "title", "pid", beta, cc A, cc F, cc R, cc V, cc O)` --- a tuple of type, title, project identifier, body content, attributes, floats, relations, views, and child objects.
>
> **Syntax:** `##...###### [TypeRef:] Title [@PID]`
>
> **Full specification:** See the CommonSpec Language Specification for the complete grammar, type inference, PID auto-generation, and examples.
