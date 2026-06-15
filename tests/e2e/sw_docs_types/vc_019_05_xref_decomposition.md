# Software Decomposition Cross-References @SDD-DECOMP-XREF

Exercises cross-references to software decomposition elements (CSC/CSU) in the
`sw_docs` model. With XREF_DECOMPOSITION defined as a LABEL_REF (`#`), a `@`-PID
link resolves as a generic section cross-reference (XREF_SEC, since CSC/CSU
extend SECTION), while a `#`-label link resolves to the type-specific
XREF_DECOMPOSITION.

## CSC: Core Services @CSC-CORE-001

> component_type: Service

> path: src/auth/

Core component that groups authentication services.

## CSU: Auth Service @CSU-AUTH-001

> file_path: src/auth/service.lua

Implementation unit for authentication logic.

## FD: Authentication Design @FD-AUTH-001

By PID (generic section xref): [CSC-CORE-001](@) and [CSU-AUTH-001](@).

By label (type-specific decomposition xref): [csc:core-services](#) and
[csu:auth-service](#).
