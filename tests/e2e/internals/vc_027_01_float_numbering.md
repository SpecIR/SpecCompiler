# spec: Float Numbering @SPEC-FN-017

## section: Interleaved Float Types @VC-INT-017

This test verifies that floats are numbered sequentially within their
counter groups, and that different counter groups maintain independent counters.
Figures and tables are interleaved to confirm counters do not interfere.

```fig:fig-alpha{caption="Alpha Architecture"}
alpha.png
```

```csv:tab-one{caption="First Data Summary"}
Product,Price
Widget,19.99
Gadget,29.99
```

```fig:fig-beta{caption="Beta Component"}
beta.png
```

```src.lua:code-demo{caption="Lua Hello World"}
local function hello()
    return "world"
end
```

```csv:tab-two{caption="Second Data Summary"}
Color,Count
Red,10
Blue,20
```

```fig:fig-gamma{caption="Gamma Deployment"}
gamma.png
```

```fig:fig-delta{caption="Delta Network"}
delta.png
```
