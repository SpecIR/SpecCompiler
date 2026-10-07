# Mermaid Test @SPEC-FLOAT-004

## Sequence Diagram

```mermaid:sequence-example{caption="User Login Sequence"}
sequenceDiagram
    actor User
    participant App as Web App
    participant DB as Auth DB

    User->>App: Login Request
    App->>DB: Validate Credentials
    DB-->>App: Success
    App-->>User: Session Token
```

## Flowchart

```mmd:flow-example{caption="Build Flow"}
flowchart LR
    A[CommonSpec] --> B[SpecIR]
    B --> C[DOCX]
    B --> D[HTML]
```

See [mermaid:sequence-example](#) and [mmd:flow-example](#).
