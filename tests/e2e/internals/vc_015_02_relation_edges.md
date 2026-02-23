# spec: Relation Edge Cases @SPEC-INT-016

## HLR: Existing Requirement @REQ-EDGE-001

A requirement that exists for linking.

> priority: High

## LLR: Valid PID Link @LLR-VALID

This object has a valid PID traceability link.

> traceability: [REQ-EDGE-001](@)

## LLR: Missing Target @LLR-MISSING

This object references a target that does not exist.

> traceability: [REQ-NONEXISTENT](@)

## LLR: Header Reference @LLR-HDR-REF

This object references another by header anchor.

> traceability: [REQ-EDGE-001](#)
