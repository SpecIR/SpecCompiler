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
