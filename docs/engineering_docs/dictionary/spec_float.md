### DIC: Spec Float @SpecIR-03

A **Spec Float** represents a floating element like a figure, table, or diagram. Floats are created from fenced code blocks with a `TypeRef:Label` pattern. They are automatically numbered within their counter group and can be cross-referenced by their label. Some floats require external rendering (e.g., PlantUML diagrams).

> description:
>
> **Formal definition:** `$: F = (tau, "label", cc "kv", "content")` --- a tuple of type, label, key-value metadata, and raw content.
>
> **Syntax:** `` ```TypeRef:Label[{Key=Value, ...}] Content ``` ``
>
> **Full specification:** See the CommonSpec Language Specification for float types, aliases, counter groups, and examples.
