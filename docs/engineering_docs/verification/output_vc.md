## Output Verification Cases

### VC: Document Assembly @VC-031

Verify documents are correctly assembled from database.

> objective: Confirm Assembler reconstructs complete document

> verification_method: Test

> approach:
> - Process document through TRANSFORM phase
> - Call Assembler.assemble_document()
> - Verify output contains all spec_objects and spec_floats in order

> pass_criteria:
> - Document title from specifications.header_ast
> - All objects in file_seq order
> - Floats embedded at correct positions
> - Views materialized with resolved content

> traceability: [HLR-OUT-001](@), [LLR-070](@), [LLR-071](@), [LLR-072](@)


### VC: Float Resolution @VC-032

Verify floats are resolved with rendered content.

> objective: Confirm raw_ast replaced with resolved_ast

> verification_method: Test

> approach:
> - Process document with PlantUML float
> - Run float_resolver
> - Verify resolved_ast contains SVG image

> pass_criteria:
> - PlantUML code blocks converted to SVG images
> - ECharts blocks converted to PNG images
> - Math blocks converted to OMML or MathML
> - resolved_ast non-NULL after resolution
> - Resolved floats wrapped in Div with semantic classes (`speccompiler-float`, type-specific class)
> - Bookmark anchors present on resolved float Divs
> - Captions include type prefix and sequential number

> traceability: [HLR-OUT-002](@), [LLR-073](@), [LLR-074](@), [LLR-075](@)


### VC: Float Numbering @VC-027

Verify floats receive sequential numbers.

> objective: Confirm [dic:counter-group](#) share numbering

> verification_method: Test

> approach:
> - Process 2 documents with figures and charts
> - Run float_numbering
> - Query spec_floats.number values

> pass_criteria:
> - Numbers assigned sequentially within counter_group
> - FIGURE and CHART share same counter (both FIGURE group)
> - TABLE has separate counter
> - Numbers span across documents

> traceability: [HLR-OUT-003](@), [LLR-076](@), [LLR-077](@)


### VC: Multi-Format Output @VC-028

Verify multiple output formats generated.

> objective: Confirm DOCX and HTML5 both produced

> verification_method: Demonstration

> approach:
> - Configure project with outputs: [{format: docx}, {format: html5}]
> - Build project
> - Verify both files created in build directory

> pass_criteria:
> - DOCX file generated at configured path
> - HTML5 file generated at configured path
> - Both contain same content
> - Output cache tracks each format separately

> traceability: [HLR-OUT-004](@), [LLR-078](@), [LLR-079](@)


### VC: DOCX Generation @VC-029

Verify DOCX output uses reference document.

> objective: Confirm styles applied from reference.docx

> verification_method: Test

> approach:
> - Execute markdown-driven preset loader probe with layered DOCX preset files
> - Verify extends-chain merge, optional format styles, and validation behavior
> - Verify preset lookup and style resolution for DOCX float/object rendering paths

> pass_criteria:
> - Preset files load and merge according to extends-chain precedence
> - Circular and missing-base extends chains fail with deterministic errors
> - Heading styles match reference document
> - Custom styles (Caption, Code) applied correctly
> - Page layout matches reference
> - OOXML postprocessing applied

> traceability: [HLR-OUT-005](@), [LLR-OUT-029-01](@)


### VC: HTML5 Generation @VC-030

Verify HTML5 output is web-ready.

> objective: Confirm HTML5 includes navigation and styling

> verification_method: Demonstration

> approach:
> - Generate HTML5 output
> - Open in browser
> - Verify navigation, styling, and cross-references work

> pass_criteria:
> - HTML5 file renders correctly in browser
> - Internal links (#anchors) navigate correctly
> - CSS styles applied
> - Search index generated if configured

> traceability: [HLR-OUT-006](@), [LLR-080](@), [LLR-081](@)


### VC: Document Assembly @VC-OUT-001

Verify document structure, ordering, and float/view inclusion in assembled output.

> objective: Confirm that the assembler produces a Pandoc document with correct specification title Div, section headers in document order, float captions, and consumed attribute blockquotes.

> verification_method: Test

> approach:
> - Process test document with specification header, two sections, a float with caption, and an attribute blockquote
> - Execute pipeline through all five phases with JSON output
> - Oracle verifies spec title Div, header order, caption presence, and attribute consumption

> pass_criteria:
> - First block is spec title Div with correct PID
> - Section headers appear in document order
> - Float caption with class "speccompiler-caption" present
> - Attribute-pattern blockquotes consumed by TRANSFORM

> traceability: [HLR-OUT-001](@), [LLR-070](@), [LLR-071](@), [LLR-072](@)


### VC: Render Decoration @VC-OUT-004

Verify header classes, bookmarks, and structural decorations in rendered output.

> objective: Confirm that render utilities apply correct CSS classes, bookmark anchors, and structural decorations to spec objects during EMIT phase.

> verification_method: Test

> approach:
> - Process test document with typed spec objects
> - Execute pipeline through all five phases with JSON output
> - Oracle verifies Div wrappers, classes, and bookmark anchors

> pass_criteria:
> - Headers receive appropriate Div wrappers with type-based classes
> - Bookmark anchors inserted for cross-reference navigation
> - Structural decoration preserves document semantics

> traceability: [HLR-OUT-001](@), [LLR-070](@), [LLR-071](@), [LLR-072](@)


### VC: Spec Object Render Handler @VC-OUT-005

Verify that object type handlers are loaded and dispatched during TRANSFORM phase, and that composite object heading IDs are patched.

> objective: Confirm that load_type_handler loads object type modules, on_render_SpecObject dispatches to type-specific renderers producing semantic output, and composite heading IDs are patched to match their PIDs.

> verification_method: Test

> approach:
> - Process test document with COVER, EXEC_SUMMARY, and SECTION objects
> - Execute pipeline through all five phases with JSON output
> - Oracle verifies cover semantic Divs, section markers, and composite heading presence

> pass_criteria:
> - COVER type handler invoked: cover-title, cover-subtitle, cover-author, cover-date, cover-docid, cover-version Divs present
> - Cover section markers (RawBlocks) emitted
> - Composite objects (EXEC_SUMMARY, SECTION) retain headers after heading ID patching

> traceability: [HLR-EXT-001](@), [HLR-OUT-001](@), [LLR-094](@)


### VC: Full-Text Search Indexing @VC-OUT-007

Verify that [dic:full-text-search](#) virtual tables are populated with specification content during the [dic:emit-phase](#) phase.

> objective: Confirm FTS5 tables contain indexed content from spec objects, attributes, and floats

> verification_method: Test

> approach:
> - Process a document with spec objects, attributes, and floats
> - Execute pipeline through EMIT phase
> - Query `fts_objects`, `fts_attributes`, and `fts_floats` tables
> - Verify search queries return expected results

> pass_criteria:
> - `fts_objects` contains entries for all spec object titles and body text
> - `fts_attributes` contains entries for all string attribute values
> - `fts_floats` contains entries for float captions and raw content
> - FTS5 MATCH queries return correct results for known content
> - AST content is converted to plain text before indexing (no JSON fragments)

> traceability: [HLR-OUT-007](@), [LLR-082](@), [LLR-083](@)


### VC: Heading Hierarchy Well-formedness @VC-OUT-008

Verify that header levels assembled across cross-file includes form a well-formed tree, that the renderer maps them to the correct heading depth, and that structurally invalid hierarchies are rejected before emission.

> objective: Confirm that the `object_broken_hierarchy` analyze query rejects skipped heading levels and orphaned roots, that a heading's level survives deep include nesting unchanged, and that the assembler maps valid levels to the correct DOCX Heading style (siblings share a style, children nest one deeper, ascending returns to the shallower style).

> verification_method: Test

> approach:
> - Build a five-file-deep include chain mixing descents, an ascent (level 4 back to level 2), and sibling chapters; generate DOCX and assert the `w:pStyle` of each heading in document order
> - Build fixtures with a skipped level (`##` then `####`) and with an orphaned root (a document opening at level 3 with a shallower level-2 heading later, including the case where the chapter is one include deeper than the section)
> - Build a contiguous multi-level control with an ascent

> pass_criteria:
> - Include nesting never changes a heading's level; level is governed only by the markdown `#`-count
> - Valid hierarchy maps to `Heading1/2/3` so that siblings share a style, each child is exactly one level deeper, and an ascent returns to the shallower style
> - A skipped level raises an `object_broken_hierarchy` error naming the skipped level
> - An orphaned root raises an `object_broken_hierarchy` error, including when the parent chapter is one include deep
> - The contiguous control raises no `object_broken_hierarchy` diagnostic

> traceability: [HLR-OUT-001](@), [HLR-PIPE-008](@)


### VC: Section Scope Termination @VC-OUT-009

Verify that a `----` thematic break closes the current section's scope, is consumed from output, and that empty headings are rejected.

> objective: Confirm that a `----` truncates the enclosing spec object's `end_line` (so trailing content/floats are contained by the parent), that the marker produces no horizontal rule in the DOCX, that content after the marker keeps its document position, and that an empty heading is reported by `object_broken_hierarchy`.

> verification_method: Test

> approach:
> - Build a section containing body, a `----`, and trailing content; query `spec_objects.end_line` and assert it truncates at the marker
> - Generate DOCX and assert no horizontal-rule border is emitted and the trailing content is still present in document order
> - Build a fixture with an empty `##` heading and assert an `object_broken_hierarchy` error is raised

> pass_criteria:
> - The section's `end_line` ends at the last block before the `----`, not at the next header
> - The DOCX contains no horizontal-rule paragraph for the consumed marker
> - Content following the `----` renders in its original position
> - An empty heading raises `object_broken_hierarchy` and the message directs the author to use `----`

> traceability: [HLR-PIPE-012](@), [HLR-OUT-001](@)


### VC: Cross-Format Heading Consistency @VC-OUT-010

Verify that LaTeX and DOCX render the same heading at the same depth, since both are produced from one assembled IR.

> objective: Confirm that a heading maps to the same depth in every output format — a section is `\section` in LaTeX and Heading2 in DOCX, never one nesting level deeper in one format than the other.

> verification_method: Test

> approach:
> - Build one multi-level fixture (chapter / section / subsection) to both LaTeX and DOCX
> - Extract the ordered (depth, title) sequence from each: LaTeX `\chapter`/`\section`/`\subsection` -> 1/2/3; DOCX Heading1/2/3 -> 1/2/3
> - Assert the two sequences are identical

> pass_criteria:
> - The number of headings matches across formats
> - Each heading's depth is identical in LaTeX and DOCX

> traceability: [HLR-OUT-001](@), [HLR-OUT-004](@)
