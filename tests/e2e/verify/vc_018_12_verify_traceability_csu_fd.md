# SDD: CSU-FD Traceability Test @SDD-CSU-FD-TEST

> version: 1.0

## CSU: Orphan Unit @CSU-ORPHAN

A CSU with no FD allocated to it.

Expected error: **traceability_csu_to_fd** (view_traceability_csu_missing_fd)

> file_path: src/orphan.lua

## FD: Orphan Function @FD-ORPHAN

An FD with no link to any CSU.

Expected error: **traceability_fd_to_csu** (view_traceability_fd_missing_csu)

> status: Draft

## CSU: Linked Unit @CSU-LINKED

A CSU that has an FD properly allocated (control case).

> file_path: src/linked.lua

## FD: Linked Function @FD-LINKED

An FD properly linked to a CSU (control case).

> status: Approved

Implements [CSU-LINKED](@).
