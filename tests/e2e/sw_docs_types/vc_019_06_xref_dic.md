# Dictionary Cross-References @SRS-DIC-XREF

Exercises dictionary entries in the `sw_docs` model. With XREF_DIC defined as a
LABEL_REF (`#`), a `@`-PID link resolves as a generic section cross-reference
(XREF_SEC, since DIC extends SECTION), while a `#`-label link resolves to the
type-specific XREF_DIC.

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

By PID (generic section xref): [DIC-AUTH-001](@) and [DIC-TOKEN-001](@).

By label (type-specific dictionary xref): [dic:authentication](#) and
[dic:session-token](#).

> status: Approved

> priority: High
