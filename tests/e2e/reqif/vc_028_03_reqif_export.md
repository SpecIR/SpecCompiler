# ReqIF Export @SRS-REQIF

## SF: Export Root @SF-REQIF

Root software function for ReqIF export tests.

> status: Approved

> description: This is a short description with **bold text** and a link to [HLR-REQIF-001](@).

## HLR: First Requirement @HLR-REQIF-001

The system shall export requirements to ReqIF.

> status: Approved

> priority: High

> rationale: The exporter must preserve *rich text* markup for tool interoperability.

> belongs_to: [SF-REQIF](@)

## HLR: Second Requirement @HLR-REQIF-002

The system shall preserve relations in the exported ReqIF.

> status: Draft

> priority: Mid

> rationale: Relations are required for traceability and roundtrips.

> traceability: [HLR-REQIF-001](@)

## SYMBOL: Complexity Sample @SYMBOL-REQIF

Sample symbol object to exercise INT→INTEGER normalization.

> kind: function

> source: src/main.c:10

> complexity: 5

