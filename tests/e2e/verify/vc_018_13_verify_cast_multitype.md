# SPEC: Multi-Type Cast Failure Test @SPEC-CAST-MULTI

This specification exercises multiple datatype cast failures at spec and object level.
Uses explicit SPEC type prefix to access all 7 attribute datatypes.

Expected errors: **invalid_cast** for INTEGER, REAL, BOOLEAN, DATE (spec-level) and ENUM (object-level).
Expected non-errors: XHTML and valid ENUM must NOT trigger invalid_cast.

> version: 1.0

> build_number: not-a-number

> progress: not-a-real

> is_stable: not-a-bool

> release_date: 2024/01/01

> stage: Alpha

> notes: Some **valid** XHTML content

## HLR: Object ENUM Cast Failure @HLR-CAST-ENUM

This object has an invalid enum value for priority, triggering object-level cast failure.

> priority: InvalidPriority

## HLR: Valid Control @HLR-CAST-CTRL

This object has all valid attributes and must NOT trigger any cast failure.

> priority: High

> status: Draft
