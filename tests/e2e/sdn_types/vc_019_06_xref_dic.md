# Dictionary Cross-References @SRS-DIC-XREF

Exercises dictionary entries and PID-based dictionary references in the
`sw_docs` model.

## DIC: Authentication @DIC-AUTH-001

> term: Authentication

> acronym: AUTH

> domain: Security

> status: Approved

Mechanism for establishing and validating identity.

## DIC: Session Token @DIC-TOKEN-001

> term: Session Token

> domain: Security

> status: Approved

Opaque credential issued after successful authentication.

## HLR: Login Requirement @HLR-DIC-001

The login flow depends on [DIC-AUTH-001](@) and emits a [DIC-TOKEN-001](@).

> status: Approved

> priority: High
