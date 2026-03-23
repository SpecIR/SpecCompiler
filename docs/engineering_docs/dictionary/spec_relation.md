### DIC: Spec Relation @SpecIR-05

A **Spec Relation** represents a traceability link between specification elements. Relations are created from Markdown links where the link target (URL) acts as a **selector** that drives type inference. The relation type is not authored explicitly --- it is inferred by constraint matching: each relation type defines optional constraints on selector, source attribute, source type, and target type. The most specific match (most non-NULL constraints) wins.

> description:
>
> **Formal definition:** `$: R = (s, t, sigma, alpha)` --- a 4-tuple of source object, target element, link selector, and source attribute.
>
> **Type inference:** `$: rho = "infer"(sigma, alpha, tau_s, tau_t)` --- the relation type is inferred by constraint matching with most-specific-wins across selector, attribute, source type, and target type.
>
> **Syntax:** `[Target](selector)` where the URL starts with `@` or `#`. Selectors are not hardcoded --- they are defined by relation types in the model (e.g., `PID_REF` defines `@`, `LABEL_REF` defines `#`, `XREF_CITATION` defines `@cite,@citep`). Models can register any `@...` or `#...` selector.
>
> **Full specification:** See the CommonSpec Language Specification for the complete inference algorithm and examples.
