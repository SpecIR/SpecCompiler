# OOXML Validation Test @SPEC-OOXML

> version: 1.0

> status: Draft

## Introduction

This document exercises key OOXML generation paths to ensure the produced
DOCX archive is structurally valid.

## Styled Content

**Bold text**, *italic text*, and `inline code`.

A paragraph with [a link](https://example.com) and a footnote reference.

### Heading Level 3

Nested heading content with **mixed** *formatting*.

#### Heading Level 4

Deeper nesting for style coverage.

## List Content

Bullet list:

- First bullet
- Second bullet with **bold**
- Third bullet

Numbered list:

1. Step one
2. Step two
3. Step three

## Table Content

```csv:ooxml-table{caption="Validation Test Table"}
Column A,Column B,Column C
alpha,100,pass
beta,200,pass
gamma,300,pass
```

## Cross References

See [csv:ooxml-table](#) for the table.

## Block Quote

> This is a block quote that should render as styled content
> in the DOCX output without corrupting the XML structure.

## Code Block

```lua
-- A code listing for OOXML coverage
local function hello()
    print("Hello from OOXML test")
end
```
