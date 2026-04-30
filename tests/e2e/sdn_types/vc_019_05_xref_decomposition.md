# Software Decomposition Cross-References @SDD-DECOMP-XREF

Exercises PID-based cross-references to software decomposition elements.

## CSC: Core Services @CSC-CORE-001

> component_type: Service

> path: src/auth/

Core component that groups authentication services.

## CSU: Auth Service @CSU-AUTH-001

> file_path: src/auth/service.lua

Implementation unit for authentication logic.

## FD: Authentication Design @FD-AUTH-001

The design allocates behavior to [CSC-CORE-001](@) and details the
implementation unit [CSU-AUTH-001](@).
