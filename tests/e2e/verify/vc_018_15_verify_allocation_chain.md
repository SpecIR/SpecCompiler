# SRS: HLR Allocation Chain @SRS-VERIFY-ALLOC

> version: 1.0

## SF: Complete Function @SF-1

> status: Approved

Fully allocated grouping.

### HLR: Allocated Requirement @HLR-1

> status: Approved

Fully allocated (control).

## SF: Orphan Function @SF-2

> status: Draft

No design realization.

### HLR: Unallocated Requirement @HLR-2

> status: Draft

Not allocated (kills relax_and on sf / r_realizes / r_belongs).

## SF: Realized Without Component @SF-3

> status: Draft

Realized by FD-3 but FD-3 links no CSC.

### HLR: Half Allocated @HLR-3

> status: Draft

Kills drop csc.type_ref, relax_and csc, relax_and fd.

## SF: Body Linked Function @SF-4

> status: Draft

Referenced by FD-4 only in body text (XREF_SEC, not REALIZES).

### HLR: Body Linked Requirement @HLR-4

> status: Draft

Kills drop r_realizes.type_ref = 'REALIZES'.

## HLR: Top Level Requirement @HLR-5

> status: Draft

> traceability: [SF-1](@)

Not nested under an SF, but has a TRACES_TO link to SF-1. Kills drop r_belongs.type_ref = 'BELONGS'.

## FD: Complete Design @FD-1

> status: Approved

> traceability: [SF-1](@)

Realizes SF-1 via [CSC-1](@), implemented by [CSU-1](@).

## FD: Component-less Design @FD-3

> status: Draft

> traceability: [SF-3](@)

Realizes SF-3 but references no component.

## FD: Body Reference Design @FD-4

> status: Draft

Mentions [SF-4](@) in prose only, and links [CSC-1](@).

## CSC: Allocation Component @CSC-1

> component_type: Service

> path: src/alloc/

Component receiving the allocation.

## CSU: Allocation Unit @CSU-1

> file_path: src/alloc/unit.lua

> traceability: [CSC-1](@)

Unit implementing the component.
