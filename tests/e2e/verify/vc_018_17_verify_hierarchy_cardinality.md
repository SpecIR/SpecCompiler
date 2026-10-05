# SDD: Hierarchy, Cardinality and Numeric Attributes @SDD-VERIFY-STRUCT

This test exercises structural and numeric analyze queries that no other fixture reaches.

> version: 1.0

## CSC: Structure Component @CSC-STRUCT

> component_type: Package

> path: src/struct/

### CSU: Structure Unit @CSU-STRUCT

> file_path: src/struct/unit.lua

##### SYMBOL: Skipped Level Symbol @SYM-SKIP

This heading jumps from level 3 to level 5.

Expected error: **object_broken_hierarchy** (skipped_level)

> kind: function

> complexity: 7

### SYMBOL: Duplicate Attribute Symbol @SYM-DUP

The `kind` attribute is declared twice on one object.

Expected error: **cardinality_over** (view_object_cardinality_over)

> kind: function

> kind: method

> complexity: 3

### SYMBOL: Bad Complexity Symbol @SYM-BADINT

The INTEGER attribute `complexity` receives a non-numeric value.

Expected error: **invalid_cast** (object-level INTEGER branch)

> kind: function

> complexity: not-a-number

### SYMBOL: Valid Control Symbol @SYM-CTRL

Valid numeric attribute; must not be flagged by any query.

> kind: function

> complexity: 12
