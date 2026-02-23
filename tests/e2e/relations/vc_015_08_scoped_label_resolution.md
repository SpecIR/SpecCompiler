# Scoped Label Resolution @SPEC-SCOPED

Verify that # label resolution uses scoped resolution (closest to global).

## Alpha @ALPHA

Alpha has a figure labeled "diagram".

```fig:diagram{caption="Alpha Diagram"}
alpha.png
```

Local reference resolves to Alpha's diagram: [fig:diagram](#).

## Beta @BETA

Beta has a figure with the SAME label "diagram".

```fig:diagram{caption="Beta Diagram"}
beta.png
```

Local reference resolves to Beta's diagram: [fig:diagram](#).

## Gamma @GAMMA

Gamma has a unique figure.

```fig:unique{caption="Gamma Unique"}
gamma.png
```

Unique reference (unambiguous, only exists in Gamma): [fig:unique](#).

Explicit scope to Alpha's diagram: [ALPHA:fig:diagram](#).

Explicit scope to Beta's diagram: [BETA:fig:diagram](#).

Ambiguous reference from outside both scopes: [fig:diagram](#).

## Delta @DELTA

Object label reference within same spec: [section:alpha](#).
