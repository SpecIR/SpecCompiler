### DIC: Spec View @SpecIR-06

A **Spec View** represents a dynamic query or generated content block. Views are materialized during the TRANSFORM phase and can generate tables of contents (TOC), lists of figures (LOF), or custom queries, abbreviations, and inline math. Views enable dynamic document assembly based on specification data.

> description:
>
> **Formal definition:** `$: V = (tau, omega)` --- a pair of view type and parameter string.
>
> **Syntax:** `` `TypeRef:[ViewParam]` ``
>
> **Full specification:** See the CommonSpec Language Specification for view types, materialization strategies, and examples.
