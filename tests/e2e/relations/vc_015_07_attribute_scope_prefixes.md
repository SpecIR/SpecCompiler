# Scoped Attribute and Prefix Relation Coverage @SPEC-REL-005

This test stresses relation parsing and scoped resolution paths.

## Scope A @SRC-A

```fig:shared-a{caption="Scope A Figure"}
scope-a.png
```

## Scope B @SRC-B

```fig:shared-b{caption="Scope B Figure"}
scope-b.png
```

## Relation Host @LLR-500

> rationale: Scoped [SRC-B:figure:shared-b](#), cite [doe2024](@cite), and object [SRC-B](@).

Direct float ref: [figure:shared-a](#).
Unknown prefix ref: [xfoo:bar](#).
PID ref: [SRC-A](@).
Header style ref: [#SRC-A](@).
