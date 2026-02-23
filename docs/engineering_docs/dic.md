# SpecCompiler Core Data Dictionary @DIC-001

## SpecIR Types

SpecIR (see [SpecIR](@)) is the data model that SpecCompiler builds from source Markdown during the [TERM-19](@) phase. The core task of parsing is to *lower* Markdown annotations into a set of typed content tables that the [TERM-15](@) can analyze, transform, verify, and emit. The entries below define each of these six content tables as a formal tuple specifying the Markdown syntax that produces it.

```{.include}
dictionary/specification.md
```

```{.include}
dictionary/spec_object.md
```

```{.include}
dictionary/spec_float.md
```

```{.include}
dictionary/attribute.md
```

```{.include}
dictionary/spec_relation.md
```

```{.include}
dictionary/spec_view.md
```
