# Verify Relation Errors @SVC-VERIFY-RELATIONS

This test intentionally triggers relation errors to verify the proof view system.

> version: 1.0

## HLR: Target for Valid References @HLR-TARGET-VALID

This is a valid requirement that serves as a target for cross-references.

> status: Approved

> priority: High

## HLR: Another Valid Target @HLR-TARGET-TWO

Another valid requirement for testing multiple references.

> status: Approved

> priority: Mid

## Section: Unresolved References @SEC-UNRESOLVED

### unresolved_relation: Unresolved Link

This paragraph contains a link to a non-existent object: [NONEXISTENT-ID](@).

Expected error: **unresolved_relation** (view_relation_unresolved)

### unresolved_relation: Another Unresolved Link

Reference to another non-existent object: [DOES-NOT-EXIST](@).

Expected error: **unresolved_relation** (view_relation_unresolved)

## Section: Float Reference Errors @SEC-FLOAT-REFS

### unresolved_relation: Unresolved Float Reference

Reference to a non-existent figure: see [fig:nonexistent-figure](#).

Expected error: **unresolved_relation** (view_relation_unresolved)

### ambiguous_relation: Ambiguous Float Reference (if applicable)

If multiple floats match, this should trigger an ambiguous reference warning.

## Section: Ambiguous Scope A @SEC-AMBIG-A

```fig:ambiguous-figure{caption="Ambiguous Figure One"}
ambiguous-one.png
```

## Section: Ambiguous Scope B @SEC-AMBIG-B

```fig:ambiguous-figure{caption="Ambiguous Figure Two"}
ambiguous-two.png
```

## Section: Ambiguous Reference @SEC-AMBIG-REF

Reference to duplicated label: [fig:ambiguous-figure](#).

Expected warning: **ambiguous_relation** (view_relation_ambiguous)

## Section: Same-Parent Duplicates @SEC-SAME-PARENT

Two floats with the same label under the SAME parent object trigger float_duplicate_label.

```fig:same-parent-dup{caption="First Under Same Parent"}
first.png
```

```fig:same-parent-dup{caption="Second Under Same Parent"}
second.png
```

Expected error: **float_duplicate_label** (view_float_duplicate_label) -- same label under same parent

## Section: Valid Reference Controls @SEC-VALID-REFS

### Valid Object Reference

This is a valid reference to an existing object: [HLR-TARGET-VALID](@).

### Valid Multiple References

Referencing multiple valid targets: [HLR-TARGET-VALID](@) and [HLR-TARGET-TWO](@).

