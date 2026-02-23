## Types Domain Requirements

### SF: Type System @SF-003

Dynamic type system providing typed containers for [SpecIR-01](@), [SpecIR-02](@), [SpecIR-03](@), [SpecIR-06](@), [SpecIR-05](@), and [SpecIR-04](@).

> description: Groups requirements for the six core containers that store parsed specification
> data plus the proof-view validation framework.

> rationale: A typed container model enables schema validation, type-specific rendering,
> and data integrity checking through SQL proof views.

### HLR: Specifications Container @HLR-TYPE-001

The type system shall provide a specifications container for registering document-level specification records.

> description: The `specifications` table stores metadata for each specification document parsed during [TERM-19](@) phase:
>
> - `identifier`: Unique specification ID derived from filename (e.g., "srs-main")
> - `root_path`: Source file path for the specification
> - `long_name`: Human-readable title extracted from L1 header
> - `type_ref`: Specification type (validated against `spec_specification_types`)
> - `pid`: Optional PID from @PID syntax in L1 header
>
> L1 headers register as specifications. Type validation checks `spec_specification_types` table. Invalid types fall back to default or emit warning.

> rationale: Specifications represent the top-level organizational unit for document hierarchies. Storing specification metadata enables cross-document linking and multi-document project support.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Spec Objects Container @HLR-TYPE-002

The type system shall provide a spec_objects container for hierarchical specification objects.

> description: The `spec_objects` table stores structured specification items extracted from L2+ headers:
>
> - `identifier`: SHA1 hash of source path + line + title (content-addressable)
> - `specification_ref`: Foreign key to parent specification
> - `type_ref`: Object type (validated against `spec_object_types`)
> - `from_file`: Source file path
> - `file_seq`: Document order sequence number
> - `pid`: Project ID from @PID syntax (e.g., "REQ-001")
> - `title_text`: Header text without type prefix or PID
> - `label`: Unified label for cross-referencing (format: `{type_lower}:{title_slug}`)
> - `level`: Header level (2-6)
> - `start_line`, `end_line`: Source line range
> - `ast`: Serialized Pandoc AST (JSON) for section content
>
> Type resolution order: explicit TYPE: prefix, implicit alias lookup, default type fallback.

> rationale: Content-addressable identifiers enable change detection for incremental builds. PID-based anchors provide stable cross-references independent of title changes.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Spec Floats Container @HLR-TYPE-003

The type system shall provide a spec_floats container for numbered floating content (figures, tables, listings).

> description: The `spec_floats` table stores content blocks that receive sequential numbering:
>
> - `identifier`: Short format "float-{8-char-sha1}" for DOCX compatibility
> - `specification_ref`: Foreign key to parent specification
> - `type_ref`: Float type resolved from aliases (e.g., "csv" -> "TABLE", "puml" -> "FIGURE")
> - `from_file`: Source file path
> - `file_seq`: Document order for numbering
> - `label`: User-provided label for cross-referencing
> - `number`: Sequential number within counter_group (assigned in [TERM-22](@))
> - `caption`: Caption text from attributes
> - `raw_content`: Original code block text
> - `raw_ast`: Serialized Pandoc CodeBlock (JSON)
> - `parent_object_ref`: Foreign key to containing spec_object
> - `attributes`: JSON-serialized attributes (caption, source, language)
> - `syntax_key`: Original class syntax for backend matching
>
> [TERM-28](@) share numbering (e.g., FIGURE, CHART, PLANTUML all increment "FIGURE" counter).

> rationale: Type aliasing supports user-friendly syntax (e.g., `csv:data` instead of `TABLE:data`). Counter groups enable semantic grouping of related float types under a single numbering sequence.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Spec Views Container @HLR-TYPE-004

The type system shall provide a spec_views container for data-driven view definitions.

> description: The `spec_views` table stores view definitions from code blocks and inline syntax:
>
> - `identifier`: SHA1 hash of specification + sequence + content
> - `specification_ref`: Foreign key to parent specification
> - `view_type_ref`: Uppercase view type (e.g., "SELECT", "SYMBOL", "MATH", "ABBREV")
> - `from_file`: Source file path
> - `file_seq`: Document order sequence number
> - `raw_ast`: View definition content (SQL query, symbol path, expression)
>
> View types with `needs_external_render = 1` in `spec_view_types` are delegated to specialized renderers. Inline views use `type: content` syntax (e.g., `symbol: Class.method`).

> rationale: Separating view definitions from rendering enables format-agnostic processing. External render delegation supports complex transformations (PlantUML, charts) without core handler changes.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Spec Relations Container @HLR-TYPE-005

The type system shall provide a spec_relations container for tracking links between specification elements.

> description: The `spec_relations` table stores inter-element references:
>
> - `identifier`: SHA1 hash of specification + target + type + parent
> - `specification_ref`: Foreign key to parent specification
> - `source_ref`: Foreign key to source spec_object
> - `target_text`: Raw link target from syntax (e.g., "REQ-001", "fig:diagram")
> - `target_ref`: Resolved target identifier (populated in [TERM-20](@) phase)
> - `type_ref`: Relation type from `spec_relation_types` (e.g., "TRACES", "XREF_FIGURE")
> - `from_file`: Source file path
>
> Link syntax: `[PID](@)` for PID references, `[type:label](#)` for float references, `[@citation]` for bibliographic citations. Default relation types are determined by `is_default` and `link_selector` columns in `spec_relation_types`.

> rationale: Deferred resolution (target_text -> target_ref) enables forward references and cross-document linking. Type inference from source/target context reduces explicit markup requirements.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Spec Attributes Container @HLR-TYPE-006

The type system shall provide a spec_attributes container for structured metadata on specification objects.

> description: The `spec_attributes` table stores typed attribute values extracted from blockquote syntax:
>
> - `identifier`: SHA1 hash of specification + owner + name + value
> - `specification_ref`: Foreign key to parent specification
> - `owner_ref`: Foreign key to owning spec_object
> - `name`: Attribute name (field name without colon)
> - `raw_value`: Original string value
> - `string_value`, `int_value`, `real_value`, `bool_value`, `date_value`: Type-specific columns
> - `enum_ref`: Foreign key to `enum_values` for ENUM types
> - `ast`: JSON-serialized Pandoc AST for rich content (XHTML type)
> - `datatype`: Resolved datatype from `spec_attribute_types`
>
> Attribute syntax: `> name: value` in blockquotes following headers. Datatypes include STRING, INTEGER, REAL, BOOLEAN, DATE, ENUM, XHTML. Multi-line attributes use continuation blocks.

> rationale: Multi-column typed storage enables SQL queries with type-appropriate comparisons. Storing original AST preserves formatting for XHTML attributes with links, emphasis, or lists.

> status: Approved

> belongs_to: [SF-003](@)

### HLR: Type Validation @HLR-TYPE-007

The type system shall provide proof views that detect data integrity violations across all specification containers.

> description: Proof views are SQL queries registered in the [TERM-21](@) phase that check for constraint violations:
>
> - Specification-level (missing required attributes, invalid types)
> - Object-level (missing required, cardinality, cast failures, invalid enum/date, bounds)
> - Float-level (orphans, duplicate labels, render failures, invalid types)
> - Relation-level (unresolved, dangling, ambiguous)
> - View-level (materialization failures, query errors)
>
> The validation policy (configurable in project.yaml) determines severity: error, warn, or ignore.

> rationale: Automated validation enables early detection of specification errors before document generation. Configurable severity allows projects to gradually enforce stricter quality standards.

> status: Approved

> belongs_to: [SF-003](@)
