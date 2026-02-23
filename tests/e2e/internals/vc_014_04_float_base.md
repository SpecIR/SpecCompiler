# spec: Float Base Behavior @SPEC-INT-004

## section: Float Captions and Source @VC-INT-004

This test verifies float caption attributes, source attribution,
and counter group assignment across figure, table, and listing types.

```fig:fig-arch{caption="Architecture Overview" source="Engineering"}
architecture.png
```

```csv:tab-metrics{caption="Performance Metrics"}
Metric,Value
Latency,42ms
Throughput,1000rps
```

```src.lua:code-init{caption="Initialization Routine"}
local M = {}
function M.init()
    return true
end
return M
```
