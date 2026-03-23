# spec: Float Utilities @SPEC-INT-006

## section: Source Attribution and Positioning @VC-INT-006

This test exercises float_base decoration, positioning, and image sizing paths.

### Figure with Source and Dimensions

```fig:fig-sourced{caption="Sourced Figure" source="Engineering Team" width="400" height="300"}
sourced.png
```

### Table with Caption After

```csv:tab-after{caption="Results Summary"}
Metric,Value
CPU,85%
Memory,2GB
```

### Math Equation (Inline Caption)

```math:eq-quadratic{caption="Quadratic Formula"}
x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}
```

### Figure with Position

```fig:fig-top{caption="Top-Positioned Figure" position="t"}
positioned.png
```

### Listing without Caption

```src.lua:code-nocap{}
local x = 42
return x
```

### Figure with Page Position and Landscape

```fig:fig-landscape{caption="Landscape Figure" position="p" orientation="landscape"}
landscape.png
```
