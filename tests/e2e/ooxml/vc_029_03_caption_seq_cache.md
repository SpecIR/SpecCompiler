# Caption SEQ Cached Value Test @SPEC-OOXML-CACHE

> version: 1.0

> status: Draft

## Introduction

Verifies that the cached placeholder inside each `SEQ` field in the
DOCX output matches the float's compiled number per counter group,
so Word/LibreOffice show the correct figure/table number even before
the user updates fields (F9).

## Figure One

```fig:cache-fig-alpha{caption="Alpha figure"}
alpha.png
```

## Table One

```csv:cache-tab-one{caption="First table"}
Col,Value
a,1
b,2
```

## Figure Two

```fig:cache-fig-beta{caption="Beta figure"}
beta.png
```

## Table Two

```csv:cache-tab-two{caption="Second table"}
Col,Value
c,3
d,4
```

## Figure Three

```fig:cache-fig-gamma{caption="Gamma figure"}
gamma.png
```
