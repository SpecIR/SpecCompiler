# SpecCompiler Core Documentation

This directory contains two documentation sets, each built as an independent SpecCompiler project with its own model and configuration.

## engineering_docs/ -- Engineering Specification Set

**Model:** `sw_docs` (safety-critical traceability)

The engineering documentation for SpecCompiler Core itself, structured as a formal specification set following DO-178C and MIL-STD-498 conventions:

| Document | Description |
|----------|-------------|
| **SRS** (`srs.md`) | Software Requirements Specification -- high-level requirements |
| **SDD** (`sdd.md`) | Software Design Description -- architecture and detailed design |
| **SVC** (`svc.md`) | Software Verification Cases -- test specifications and results |
| **DIC** (`dic.md`) | Data Dictionary -- SpecIR type definitions and syntax reference |

These documents use full traceability enforcement: HLR to VC to TR, FD to CSC to CSU. Proof views (SQL validation queries) run during the VERIFY phase to detect missing traceability, unresolved references, and other constraint violations.

**This is a dogfooding example.** It demonstrates how SpecCompiler can be used to author, validate, and publish safety-critical software documentation from plain Markdown. The same pipeline that builds user projects builds its own engineering docs.

Build:

```bash
specc build docs/engineering_docs/project.yaml
```

## user_docs/ -- User-Facing Documentation

**Model:** `default` (standard content)

End-user documentation without engineering traceability overhead:

| Document | Description |
|----------|-------------|
| **Manual** (`manual.md`) | Installation, configuration, authoring syntax, and reference |
| **Creating a Model** (`guides/creating-a-model.md`) | How to create custom type models |
| **DOCX Customization** (`guides/docx-customization.md`) | How to customize Word output |

Build:

```bash
specc build docs/user_docs/project.yaml
```
