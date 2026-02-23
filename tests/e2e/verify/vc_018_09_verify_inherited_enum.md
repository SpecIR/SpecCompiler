# SRS: Inherited Enum Validation @SRS-INHERIT-TEST

> version: 1.0

## HLR: Requirement With Invalid Inherited Status @HLR-INVALID-STATUS

The `status` attribute is defined on TRACEABLE (the base type), not directly on HLR.
Valid values are: Draft, Review, Approved, Implemented.
"Pending" is not valid — this must trigger `invalid_cast`.

> status: Pending
