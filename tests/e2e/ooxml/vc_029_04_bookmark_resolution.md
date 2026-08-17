# Bookmark Resolution Test @SPEC-BMK-001

> version: 1.0

> status: Draft

## Introduction @SPEC-BMK-001-intro

`toc:`

Verifies that every hyperlink anchor and field reference in the DOCX
output resolves to a bookmark. See [SPEC-BMK-001-details](@),
[fig:bmk-figure](#), and [csv:bmk-table](#).

## Details @SPEC-BMK-001-details

Back-reference to [SPEC-BMK-001-intro](@) and forward to
[list-table:bmk-links-table](#).

```fig:bmk-figure{caption="Bookmark test figure"}
bmk.png
```

## Links Inside Table Floats @SPEC-BMK-001-tables

Links inside table float cells must also resolve (regression: links
inside table floats).

```csv:bmk-table{caption="Plain CSV table"}
Col,Value
a,1
b,2
```

```list-table:bmk-links-table{caption="Links inside a table float" header-rows=1}
* - Kind
  - Reference
* - Object link
  - See [SPEC-BMK-001-intro](@)
* - Float link
  - See [fig:bmk-figure](#)
* - Table link
  - See [csv:bmk-table](#)
```
