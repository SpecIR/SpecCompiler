# Output Formats Test @SPEC-OUT

> version: 1.0

> status: Draft

## Introduction

This document tests output format generation.

## Styled Content

**Bold text** and *italic text* and `code`.

### Heading Level 3

Nested heading content.

#### Heading Level 4

Deeper nesting.

## List Content

Bullet list:

- First item
- Second item
- Third item

Numbered list:

1. Step one
2. Step two
3. Step three

## Table Content

```csv:output-table{caption="Sample Output Table"}
Format,Extension,Status
DOCX,.docx,Supported
HTML,.html,Supported
Markdown,.md,Supported
JSON,.json,Supported
```

## Figure Content

```fig:output-figure{caption="Output Test Figure" source="Test"}
test-image.png
```

## Cross References

See [csv:output-table](#) for formats.
See [fig:output-figure](#) for the figure.
