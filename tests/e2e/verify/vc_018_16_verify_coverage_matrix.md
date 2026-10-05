# SRS: Coverage Matrix @SRS-VERIFY-COVERAGE

> version: 1.0

## HLR: Requirement A @HLR-A

> status: Approved

A requirement.

## LLR: Low A @LLR-A

> status: Draft

Targeted by DD-A traceability (TRACES_TO), no VC.

## LLR: Low B @LLR-B

> status: Draft

No relations at all.

## LLR: Low C @LLR-C

> status: Draft

Verified by VC-A (control).

## DD: Decision A @DD-A

> rationale: Because.

> traceability: [LLR-A](@)

## VC: Case A @VC-A

> verification_method: Test

> traceability: [HLR-A](@), [LLR-C](@)

Verifies HLR-A and LLR-C (control).

## VC: Case B @VC-B

> verification_method: Test

No relations.

## VC: Case C @VC-C

> verification_method: Test

Body link to [DD-A](@) only (XREF_SEC), no VERIFIES.

## TR: Result A @TR-A

> result: Pass

> traceability: [VC-A](@)

Control.

## TR: Result B @TR-B

> result: Pass

> traceability: [HLR-A](@)

Traceability to a non-VC.

## TR: Result C @TR-C

> result: Pass

No traceability at all.

## CSC: Component A @CSC-A

> component_type: Service

> path: src/a/

No inbound relation.

## CSC: Component B @CSC-B

> component_type: Service

> path: src/b/

Inbound from CSU-A (non-FD source).

## CSC: Component C @CSC-C

> component_type: Service

> path: src/c/

Inbound from FD-X (control).

## CSU: Unit A @CSU-A

> file_path: src/a.lua

> traceability: [CSC-B](@)

Also mentions [CSU-C](@) in body.

## CSU: Unit B @CSU-B

> file_path: src/b.lua

Inbound from FD-X (control).

## CSU: Unit C @CSU-C

> file_path: src/c.lua

Inbound from CSU-A body link (non-FD source).

## CSU: Unit D @CSU-D

> file_path: src/d.lua

No inbound.

## FD: Design X @FD-X

> status: Approved

Links [CSC-C](@) and [CSU-B](@) (control).

## FD: Design Y @FD-Y

> status: Draft

Links only [FD-X](@) (non-CSU target).

## FD: Design Z @FD-Z

> status: Draft

No relations.
