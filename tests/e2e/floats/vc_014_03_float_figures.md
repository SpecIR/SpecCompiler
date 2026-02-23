# Figures and Listings Test @SPEC-FLOAT-004

## Figure with Dimensions

```fig:diagram{caption="Architecture Diagram" source="Author" width=80%}
architecture.png
```

## Source Code Listing

```src.lua:lua-example{caption="Lua Function Example"}
local function process(input)
    if not input then
        return nil, "Input required"
    end
    return input:upper()
end
```

```src.python:python-example{caption="Python Class Example"}
class Handler:
    def __init__(self, name):
        self.name = name

    def process(self, data):
        return f"{self.name}: {data}"
```

## References

The [fig:diagram](#) shows the architecture.
See [src.lua:lua-example](#) for the Lua implementation.
See [src.python:python-example](#) for Python version.
