# SRS: Citation Links Are Not Unresolved Relations @SRS-VERIFY-CITE

Citation links use the `@cite` selector. They are never resolved against spec
objects, so they must not be reported as `unresolved_relation`.

> version: 1.0

## HLR: Requirement With Citation @HLR-CITE

This requirement cites an external source [smith2024](@cite) and another one
[doe2023](@citep) that no bibliography defines.

> priority: High

## HLR: Requirement With Broken Link @HLR-BROKEN

This requirement links to a missing object [MISSING-OBJ](@).

Expected error: **unresolved_relation** (view_relation_unresolved)

> priority: Mid
