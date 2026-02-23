# spec: Float Type Aliases @SPEC-INT-012

## section: Type Alias Resolution @VC-INT-012

This test verifies that float type aliases (csv, fig, src) resolve
to their canonical types (TABLE, FIGURE, LISTING) in the output.

```fig:fig-alias{caption="Figure via fig alias"}
figure-alias.png
```

```csv:tab-alias{caption="Table via csv alias"}
X,Y
1,2
```

```src.python:code-alias{caption="Listing via src alias"}
print("hello")
```
