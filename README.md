<p align="center"><em>SpecCompiler is an extensible type system for Markdown.</em></p>

<p align="center">
  <img src="assets/logo.jpg" alt="SpecCompiler logo" width="160"/>
</p>

<p align="center">
  <a href="https://github.com/SpecIR/SpecCompiler/actions/workflows/docker-publish.yml"><img src="https://github.com/SpecIR/SpecCompiler/actions/workflows/docker-publish.yml/badge.svg" alt="CI"></a>
  <a href="https://codecov.io/gh/SpecIR/SpecCompiler"><img src="https://codecov.io/gh/SpecIR/SpecCompiler/branch/main/graph/badge.svg?token=GC8S08LK2G" alt="Coverage"></a>
  <a href="https://github.com/SpecIR/SpecCompiler/blob/main/LICENSE"><img src="https://img.shields.io/github/license/SpecIR/SpecCompiler" alt="License"></a>
  <img src="https://img.shields.io/badge/status-alpha-orange" alt="Status: Alpha">
</p>

## SpecIR & SpecCompiler

SpecIR is a typed relational intermediate representation for textual specifications.

SpecCompiler is its reference implementation. It lowers Markdown into SpecIR and executes declarative structural constraints over the resulting model.

By imposing a type system on Markdown SpecCompiler guarantees referential and schema integrity: detecting invalid object kinds, missing mandatory attributes and traceability gaps at **compile time**.

> "The fundamental purpose of a type system is to prevent 
> the occurrence of execution errors during the running of 
> a program." Cardelli, [Type Systems](http://lucacardelli.name/Papers/TypeSystems.pdf)

The fundamental purpose of SpecCompiler is to prevent the occurrence of *findings* during the review of a specification.

### See It in Action

<p align="center">
  <img src="assets/demo.gif" alt="SpecCompiler demo: writing specs, catching type errors, and compiling to DOCX" width="700"/>
</p>

<p align="center"><em>Well-typed specifications don't go wrong.</em></p>

## Output

**DOCX (Print is Default):** Maps types directly to DOCX style presets and supports direct OOXML transformations. Generate branded corporate templates or academic formats.

**HTML + WASM (Web Native):** A self-contained html file bundled with SQLite.js enables queries directly in the browser without any server infrastructure.

**ReqIF (Interoperability):** Author and validate your specs in Git but emit industry-standard ReqIF to integrate with legacy RE tools.

**Anything (that Pandoc supports):** The pipeline is extensible via custom Lua filters and post-processing hooks for any format Pandoc can target.

## Quickstart

### Install

```bash
git clone https://github.com/SpecIR/SpecCompiler.git
cd SpecCompiler
```

Docker is recommended. (Linux/Mac/WSL2)
```bash
bash scripts/remote_install.sh
```

For native ubuntu/debian (builds all dependencies from source).
```bash
bash scripts/build.sh --install
```

Build the docs.

```bash
specc build docs/engineering_docs/project.yaml
specc build docs/user_docs/project.yaml 
```

[`docs/user_docs/`](docs/engineering_docs/)  contains user-facing documentation (installation, authoring syntax, configuration) serving as an example of the default type system applied to general technical publishing.

[`docs/engineering_docs/`](docs/engineering_docs/) contains a self-hosted engineering document set (SRS/SDD/SVC) illustrating how the system can be applied in regulated and safety-critical software.

## Online Documentation

- **[Manual](https://specir.github.io/SpecCompiler/manual/#/manual)**, installation, authoring syntax, configuration [(start here)](https://github.com/SpecIR/SpecCompiler/releases/download/v/manual.docx)
- **[Engineering Specs](https://specir.github.io/SpecCompiler/engineering/#/srs)**, SRS, SDD, SVC for SpecCompiler itself.

## How It Works

### A Minimal Spec

**srs.md** — a requirement:

```markdown
# SRS: Login Service

## HLR: Authenticate Users @0013

The system shall authenticate users via OAuth 2.0.

> status: Draft
```

**svc.md** — a verification case that covers it:

```markdown
# SVC: Login Verification 

## VC: Verify Authentication

Verify the authentication flow works end to end.

> objective: Confirm OAuth 2.0 login succeeds

> verification_method: Test

> traceability: [0013](@)
```

### Pandoc + SQLite Middle-End

SpecCompiler runs as a Pandoc Lua filter and adds a SQLite middle-end between Pandoc's reader and writer:

**0. Type loading (Γ).** Before any document is parsed, SpecCompiler reads
type definitions from Lua modules and INSERTs them into the IR. A type defines
what a spec object *is*: its identifier, display name, PID format, and typed
attributes.

For example, the HLR type (`models/sw_docs/types/objects/hlr.lua`):

```lua
M.object = {
    id = "HLR",
    long_name = "High-Level Requirement",
    extends = "TRACEABLE",
    attributes = {
        { name = "rationale", type = "XHTML" },
    }
}
```

Loading this module produces:

```sql
INSERT INTO spec_object_types (identifier, long_name, ...)
VALUES ('HLR', 'High-Level Requirement', ...);
```

**1. Frontend (Pandoc reader).** Parse `commonmark_x` into Pandoc AST.

**2. Middle-end (SpecCompiler).** Lower the AST into SpecIR (SQLite), apply type
rules, and assemble the transformed AST. For the two-file spec above, the
middle-end produces the following relations:

```sql
-- Specification (from the # heading)
INSERT INTO specifications (identifier, long_name, type_ref)
VALUES ('srs', 'Login Service', 'SRS');

-- Object (from the ## heading)
INSERT INTO spec_objects (specification_ref, type_ref, pid)
VALUES ('srs', 'HLR', '0013');

-- Attribute (from the > blockquote)
INSERT INTO spec_attribute_values
  (specification_ref, owner_object_id, name, raw_value, enum_ref, datatype)
VALUES ('srs', 1, 'status', 'Draft', 'TRACEABLE_status_Draft', 'ENUM');

-- Relation (from [0013](@) in svc.md's traceability attribute → inferred as VERIFIES)
INSERT INTO spec_relations
  (specification_ref, source_object_id, target_text, type_ref, link_selector, source_attribute)
VALUES ('svc', 2, '0013', 'VERIFIES', '@', 'traceability');
```

Type-checking is then a query against the IR. For example, the proof view
`invalid_cast` checks whether `'Pending'` is a legal value for
`TRACEABLE.status` — it is not (only Draft, Review, Approved, Implemented are).
And `traceability_hlr_to_vc` finds HLRs that are never the target of a
VERIFIES relation.

**3. Backend (Pandoc writer).** If no violations are found render the AST to selected formats.

**4. Post-processing (optional).** Format-specific adjustments to the emitted artifacts. For example, OOXML tweaks in DOCX output or packaging sqlite.js in HTML.

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

[THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES).
