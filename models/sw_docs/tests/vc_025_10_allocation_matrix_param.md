# SRS: Allocation Matrix Param Test @SRS-ALLOC-PARAM

> version: 1.0

> status: Draft

## SF: Complete Function @SF-ALLOC-001

> status: Approved

Functional grouping with a complete allocation chain.

### HLR: Complete Requirement @HLR-ALLOC-001

> status: Approved

The system shall have a fully allocated requirement.

## SF: Orphan Function @SF-ALLOC-002

> status: Draft

Functional grouping with no design realization.

### HLR: Unallocated Requirement @HLR-ALLOC-002

> status: Draft

The system shall have a requirement without design allocation.

## FD: Complete Design @FD-ALLOC-001

> status: Approved

> traceability: [SF-ALLOC-001](@)

Design description realizing the complete function via [CSC-ALLOC-001](@),
implemented by [CSU-ALLOC-001](@).

## CSC: Allocation Component @CSC-ALLOC-001

> component_type: Service

> path: src/alloc/

Component receiving the allocation.

## CSU: Allocation Unit @CSU-ALLOC-001

> file_path: src/alloc/unit.lua

> traceability: [CSC-ALLOC-001](@)

Unit implementing the component.

## Allocation

`allocation_matrix: status=complete`
