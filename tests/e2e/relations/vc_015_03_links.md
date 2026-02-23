# Requirements @SRS-REL

## Parent Requirement @LLR-001

This is the parent requirement.

> priority: High

## Child Requirement @LLR-002

This requirement traces to parent.

> traceability: [LLR-001](@)

## Another Child @LLR-003

Multiple traceability links.

> traceability: [LLR-001](@), [LLR-002](#)

## Typed Relations @LLR-004

Using typed relation syntax.

> implements: [LLR-001](@)

> verified_by: [LLR-005](@)

## Verification Case @LLR-005

Verifies the child requirement.

> verifies: [LLR-002](@)

> verification_method: Test
