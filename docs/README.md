# SpecCompiler Documentation

This directory contains four documentation sets. Each set is an independent SpecCompiler project with its own configuration.

## `engineering_docs/` — Engineering specifications

**Model:** `sw_docs` (safety-critical traceability)

This set specifies SpecCompiler. It follows DO-178C and MIL-STD-498 conventions.

| Document | Description |
|----------|-------------|
| **SRS** (`srs.md`) | Software Requirements Specification -- high-level requirements |
| **SDD** (`sdd.md`) | Software Design Description -- architecture and detailed design |
| **SVC** (`svc.md`) | Software Verification Cases -- test specifications and results |
| **DIC** (`dic.md`) | Data Dictionary -- SpecIR type definitions and syntax reference |

These documents enforce HLR-to-VC-to-TR and FD-to-CSC-to-CSU traceability. SQL analyze queries detect unresolved references, missing traceability, and other constraint violations.

Build:

```bash
specc build docs/engineering_docs/project.yaml
```

## `user_docs/` — User documentation

**Model:** `default` (standard content)

This set explains installation, authoring, output configuration, and model development.

| Document | Description |
|----------|-------------|
| **Manual** (`manual.md`) | Installation, configuration, authoring syntax, and reference |
| **Creating a Model** (`guides/creating-a-model.md`) | How to create custom type models |
| **DOCX Customization** (`guides/docx-customization.md`) | How to customize Word output |

Build:

```bash
specc build docs/user_docs/project.yaml
```

## `commonspec/` — CommonSpec language specification

This set defines the CommonSpec authoring language.

```bash
specc build docs/commonspec/project.yaml
```

## `specir/` — SpecIR schema specification

This set defines the SQLite intermediate representation.

```bash
specc build docs/specir/project.yaml
```
