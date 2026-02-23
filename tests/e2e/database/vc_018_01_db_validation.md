# Database Validation Test @SPEC-VALID

> version: 1.0

## Valid Requirement @REQ-VALID

Complete requirement with all required attributes.

> priority: High

> status: Approved

> verification_method: Test

## Another Valid @REQ-VALID-2

Another complete requirement.

> priority: Medium

> status: Draft

> verification_method: Inspection

## Float for View

```csv:validation-data{caption="Validation Data"}
Field,Required,Type
Name,Yes,String
Count,No,Integer
Active,Yes,Boolean
```

## Cross References

See [REQ-VALID](@) for the valid requirement.
The [csv:validation-data](#) shows the schema.
