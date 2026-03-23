# spec: Emit Float Pipeline @SPEC-INT-007

## section: Float Emission Tests @VC-INT-007

This test exercises emit_float.lua: CodeBlock replacement, handler dispatch,
bookmark generation, and caption decoration during the EMIT phase.

### Captioned Figure

```fig:fig-emit-test{caption="Architecture Diagram" source="Engineering"}
emit-test.png
```

### Captioned Table

```csv:tab-emit-data{caption="Test Results"}
Test,Status
Unit,Pass
Integration,Pass
```

### Captioned Listing

```src.lua:code-emit-sample{caption="Module Setup"}
local M = {}
function M.setup() return true end
return M
```

### Uncaptioned Code Block

```lua
-- This is a regular code block, not a float
print("hello")
```
