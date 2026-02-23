# SRS: SpecCompiler Requirements @SRS-001

> version: 1.0

## Scope

This document defines the high-level requirements for SpecCompiler , a document processing pipeline for structured specifications.

The document is organized in two parts. The first part defines the SpecIR data model, the six core types that the [TERM-15](@) operates on. The second part specifies the functional requirements, grouped into System Features ([SF-001](@) through [SF-006](@)), each decomposed into High-Level Requirements.

```{.include}
dic.md
```

## Functional Requirements

With the data model established, the following sections define the functional requirements for SpecCompiler Core. Requirements are organized into System Features (SF), each covering a distinct functional domain. Every SF is decomposed into [TERM-HLR](@)s that state what the system shall do.

```{.include}
requirements/pipeline.md
```

```{.include}
requirements/storage.md
```

```{.include}
requirements/types.md
```

The type system described above is not fixed at compile time. The following section defines how [TERM-33](@) directories extend it with custom object types, float renderers, [TERM-35](@) generators, and style presets.

```{.include}
requirements/extension.md
```

```{.include}
requirements/output.md
```

Once documents are assembled and published, the system must also guarantee that its builds are reproducible and its processing is auditable. The following section addresses these integrity concerns.

```{.include}
requirements/audit.md
```

The glossary below defines the domain vocabulary used throughout this specification. Each term corresponds to a cross-reference encountered in the requirements above and is defined here with its purpose, scope, and usage context.

```{.include}
dictionary/concepts.md
```
