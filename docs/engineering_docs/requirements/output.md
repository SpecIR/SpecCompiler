## Output Requirements

### SF: Multi-Format Publication @SF-004

Assembles transformed content and publishes DOCX/HTML5 outputs with cache-aware emission.

> description: Single-source, multi-target publication. Groups requirements for document
> assembly, float resolution/numbering, and format-specific output generation.

> rationale: Technical documentation must be publishable in multiple formats from a
> single Markdown source.

#### HLR: Document Assembly @HLR-OUT-001

The system shall reconstruct a complete Pandoc document from [dic:intermediate-representation](#) database content for each specification, preserving document order and embedding all resolved content.

> description: During the [dic:emit-phase](#) phase, the assembler queries `spec_objects` ordered by `file_seq`, decodes stored JSON [dic:abstract-syntax-tree](#) fragments back to Pandoc blocks, adjusts header levels for cross-file includes, and embeds:
>
> 1. **Specification title**: From `specifications.header_ast`, wrapped in a title Div
> 2. **Spec objects**: All objects belonging to the specification, in `file_seq` order, with their rendered body AST
> 3. **Spec floats**: Placeholder CodeBlocks for floats at their document positions (resolved later by the float emitter)
> 4. **Spec views**: Placeholder CodeBlocks for views at their document positions (expanded later by the view emitter)
>
> The assembled document includes Pandoc metadata built from specification attributes (title, author, date). The result is a valid `pandoc.Pandoc` document suitable for format-specific output.

> rationale: Decoupling parsing from rendering enables format-agnostic processing through the pipeline. Database-backed assembly allows cross-document operations (shared numbering, cross-references) that sequential file processing cannot achieve.

> status: Approved


#### HLR: Float Resolution @HLR-OUT-002

The system shall replace [dic:float](#) placeholder blocks in the assembled document with their rendered content, using results from the [dic:transform-phase](#) phase.

> description: After document assembly, the float emitter walks all blocks and replaces CodeBlock placeholders (identified by float labels) with rendered Div elements containing:
>
> 1. **Rendered content**: The `resolved_ast` from `spec_floats` (SVG images for PlantUML, parsed tables for CSV, chart images for ECharts)
> 2. **Caption**: A formatted caption with type prefix and sequential number (e.g., "Figure 1 -- Diagram Title")
> 3. **Semantic classes**: CSS classes (`speccompiler-float`, `speccompiler-caption`, type-specific class) for format-specific styling
> 4. **Bookmark anchor**: An identifier anchor for cross-reference navigation
>
> Floats whose `resolved_ast` is NULL (failed external renders) are preserved as error placeholders.

> rationale: Separating float resolution from assembly enables parallel external rendering during TRANSFORM while maintaining correct document insertion order during EMIT.

> status: Approved


#### HLR: Float Numbering @HLR-OUT-003

The system shall assign sequential numbers to [dic:float](#)s within their [dic:counter-group](#), producing a single numbering sequence across all documents in the project.

> description: During the [dic:transform-phase](#) phase, the float numberer:
>
> 1. Queries all floats across all specifications, ordered by `file_seq`
> 2. Groups floats by their `counter_group` (e.g., FIGURE, TABLE, LISTING, EQUATION)
> 3. Assigns monotonically increasing numbers within each group (starting at 1)
> 4. Float types sharing a counter_group share the same sequence (e.g., FIGURE, CHART, and PLANTUML all increment the "FIGURE" counter)
>
> The assigned numbers are stored in `spec_floats.number` and used for caption formatting and cross-reference display text.

> rationale: Consistent cross-document numbering prevents duplicate figure/table numbers and enables stable cross-references. Counter group sharing allows semantically related types (all visual content) to form natural sequences.

> status: Approved


#### HLR: Multi-Format Output @HLR-OUT-004

The system shall generate output documents in all formats specified by the project configuration, skipping outputs whose [dic:processed-intermediate-representation](#) hash matches the cached value.

> description: The emitter orchestrator iterates over `config.outputs` (an array of `{format, path}` pairs) and for each specification:
>
> 1. Serializes the assembled Pandoc document to an intermediate JSON file
> 2. Checks the output cache (`is_output_current()`) and skips generation when the P-IR hash matches
> 3. Applies format-specific Pandoc Lua filters (e.g., `docx.lua`, `html.lua` from the model's `filters/` directory)
> 4. Invokes Pandoc for format conversion
> 5. Runs format-specific postprocessors after Pandoc generation completes
> 6. Cleans up intermediate JSON files
>
> Supported output formats: DOCX, HTML5, Markdown, JSON. Multiple formats can be generated from a single pipeline execution.

> rationale: Single-source multi-target publication eliminates content duplication. Cache-aware skipping avoids regenerating unchanged outputs, reducing build times for large specification projects.

> status: Approved


#### HLR: DOCX Generation @HLR-OUT-005

The system shall generate DOCX output with style customization via preset-based reference document generation and OOXML post-processing.

> description: DOCX output generation follows this sequence:
>
> 1. **Preset loading**: Loads style preset definitions from `models/{model}/styles/presets/` with extends-chain merging and circular dependency detection
> 2. **Reference document generation**: Generates a `reference.docx` from the resolved preset containing custom Word styles (headings, captions, code blocks, table styles)
> 3. **Pandoc conversion**: Invokes Pandoc with `--reference-doc` pointing to the generated reference and format-specific Lua filters
> 4. **OOXML post-processing**: Modifies the DOCX archive to apply style fixups, numbering definitions, and structural corrections that Pandoc cannot produce natively
>
> The reference document is cached and regenerated only when the preset hash changes.

> rationale: Preset-based styling enables consistent corporate branding without manual Word template editing. OOXML post-processing addresses Pandoc limitations for advanced Word formatting requirements.

> status: Approved


#### HLR: HTML5 Generation @HLR-OUT-006

The system shall generate standalone HTML5 output with table of contents, section numbering, and embedded resources when configured.

> description: HTML5 output generation follows this sequence:
>
> 1. **Pandoc conversion**: Invokes Pandoc with HTML5-specific options from project configuration (`number_sections`, `table_of_contents`, `toc_depth`, `standalone`, `embed_resources`)
> 2. **Resource embedding**: When `embed_resources` is enabled, all CSS, JavaScript, and image assets are embedded inline for single-file distribution
> 3. **Search index**: When [dic:full-text-search](#) tables are populated, the HTML5 postprocessor bundles the search index for client-side full-text search
> 4. **Internal links**: Cross-reference `(@)` links resolve to `#anchor` URLs for in-page navigation
>
> Configuration is specified in the `html5:` section of `project.yaml`.

> rationale: Standalone HTML5 with embedded resources enables documentation distribution without web server infrastructure. FTS integration provides search capability for large specification sets.

> status: Approved


#### HLR: Full-Text Search Indexing @HLR-OUT-007

The system shall populate [dic:full-text-search](#) virtual tables during the [dic:emit-phase](#) phase to enable full-text search across specification content.

> description: The FTS indexer creates and populates three FTS5 virtual tables with Porter stemming:
>
> 1. **`fts_objects`**: Indexes spec object titles and body text, keyed by identifier and spec_id
> 2. **`fts_attributes`**: Indexes attribute names and string values, keyed by owner_ref and spec_id
> 3. **`fts_floats`**: Indexes float captions and raw source content, keyed by identifier and spec_id
>
> [dic:abstract-syntax-tree](#) content is converted to plain text before indexing.

> rationale: Full-text search enables users to find specification content across large document sets. FTS5 with Porter stemming provides standard information retrieval capabilities suitable for technical documentation.

> status: Approved

