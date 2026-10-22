## Output Design

### FD: Multi-Format Publication @FD-004

> traceability: [SF-004](@)

**Allocation:** Realized by [CSC-012](@) (Transform Handlers) and [CSC-009](@) (Emit Handlers) through [CSU-060](@) (External Render Handler) and [CSU-037](@) (Emitter Orchestrator). Output infrastructure is provided by [CSC-004](@) (Infrastructure), with format-specific utilities in [CSC-013](@) (Format Utilities), DOCX generation in [CSC-014](@) (DOCX Generation), I/O operations in [CSC-015](@) (I/O Utilities), and external process management in [CSC-016](@) (Process Management). Links inside diagram float source are resolved through [CSU-165](@) (Relation Lookup) and [CSU-166](@) (Source Links) in [CSC-011](@) (Shared Pipeline Utilities).

The multi-format publication function encompasses the TRANSFORM and EMIT pipeline phases,
covering content rendering, external subprocess rendering,
document assembly from the [dic:intermediate-representation](#) database, [dic:float](#) numbering and resolution, and
parallel output generation via Pandoc. Views (table of contents, list of
figures/tables, abbreviation lists, matrices) are rendered live at EMIT time by
their view-type render hooks querying the database, so their content always
reflects current database state — a requirement of the output cache, which keys
on the serialized render input.

**TRANSFORM Phase**: Prepares content for output through the handler stages:

- [CSU-061](@): Resolves float content that does not require external rendering
  (e.g., CSV parsing, text processing) and updates `spec_floats.resolved_ast`.

- [CSU-060](@): Coordinates parallel subprocess rendering for float types
  requiring external tools (PlantUML, ECharts, Math). Prepares tasks via renderer callbacks,
  checks output cache for hits, and spawns remaining tasks in parallel via luv `spawn_batch()`.
  Results update `resolved_ast` with output paths. Before preparing a task for a float type
  that declares a `format_link` hook, it lowers the CommonSpec links in the float source into
  the type's native hyperlink syntax (see Diagram Hyperlinks below).

- [CSU-062](@): Invokes type-specific handlers for each spec_object
  (ordered by file_seq). Type handlers provide `header()` and `body()` functions dispatched
  through the base handler wrapper. Rendered AST is merged back to `spec_objects.ast`.

- [CSU-063](@): Renders document title headers via specification type
  handlers, storing result in `specifications.header_ast`.

**EMIT Phase**: Assembles and generates output documents in multiple formats,
fulfilling multi-format output requirements:

- [CSU-039](@): Assigns sequential numbers to floats by counter_group (e.g., FIGURE,
  TABLE, LISTING, EQUATION) across all documents. Shared counter groups
  enable natural numbering where related visual content types form a single sequence.

- [CSU-034](@): Reconstructs a complete Pandoc AST from the SpecIR database
  Queries spec_objects ordered by `file_seq`, decodes JSON AST fragments,
  normalizes header levels, and assembles floats and views into the document structure.
  Metadata is built from specification attributes and the assembler returns a complete
  `pandoc.Pandoc` document.

- [CSU-040](@): Builds a lookup map of rendered float results (ast, number, caption,
  type_ref) from `spec_floats` with `resolved_ast`. The resolver queries
  the database for all floats belonging to the current specification and indexes them for
  efficient lookup during document traversal.

- [CSU-035](@): Walks assembled document blocks and replaces float placeholder CodeBlocks
  with rendered Div elements containing captions and semantic CSS classes for
  format-specific styling.

- [CSU-041](@): Replaces view placeholder blocks with materialized content from the
  TRANSFORM phase. Views are expanded inline as formatted tables, lists, or custom
  structures depending on view type. Additionally, populates FTS5 virtual tables
  (`fts_objects`, `fts_attributes`, `fts_floats`) for [dic:full-text-search](#) in the web
  application, converting AST to plain text and indexing searchable fields with Porter
  stemming.

- [CSU-042](@): Processes inline elements during emit - resolves `(@)` links to
  `#anchor` references, processes citations, and renders inline math expressions.

- [CSU-037](@): Format-agnostic orchestration for batch mode
  execution: (1) assigns float numbers globally, (2) assembles documents per
  specification, (3) resolves and transforms floats, (4) applies format-specific filters
  (docx, html), (5) serializes assembled documents to intermediate JSON via
  `pandoc.write(doc, "json")` to temporary files, (6) checks `output_cache` for staleness
  and skips generation when outputs are current, (7) spawns parallel Pandoc processes
  via luv for concurrent format conversion (docx, html5), and (8) cleans up intermediate
  JSON files after generation completes. Format-specific postprocessors run after Pandoc
  generation: DOCX postprocessing applies style fixups via OOXML manipulation, and HTML5
  postprocessing bundles assets for web application deployment.

**Diagram Hyperlinks**: CommonSpec links written inside a diagram float's source
(e.g. `Foo --> Bar : see [SEC-2](@)` in a PlantUML block) travel the same relation path as
body links. [CSU-048](@) registers them in INITIALIZE as links of the float's parent object,
using [CSU-166](@) to find them in the raw text. The type's optional `mask_comments` hook
blanks the tool's comments first, and a link preceded by `~` is literal text. RESOLVE treats
the links like any other link. In TRANSFORM, [CSU-060](@) looks each link up in [CSU-165](@)
(the lookup that [CSU-162](@) uses for body links) and replaces it with the output of the
type's `format_link` hook. PlantUML ([CSU-112](@)) emits `[[href{tooltip} label]]` and
renders the rewritten source to PNG and then SVG. In EMIT, [CSU-040](@) and [CSU-035](@)
keep the float as the PNG image and add the SVG path as the image's `svg` attribute.
[CSU-037](@) removes that attribute for every non-HTML format, and the HTML filter
([CSU-084](@)) replaces the image with the inline SVG so its anchors navigate.
The rationale is recorded in [DD-CORE-008](@).

**Infrastructure Support**: The Pandoc CLI wrapper ([CSU-079](@)) builds command arguments for multiple
output formats (docx, html5, markdown, json) with reference document, bibliography, and
filter support. The reference generator ([CSU-075](@)) creates `reference.docx` from style presets for
DOCX output styling.

**Component Interaction**

The output subsystem spans the TRANSFORM and EMIT pipeline phases, realized through
handler packages and infrastructure components.

[csc:transform-handlers](#) (Transform Handlers) prepares content for output. [csu:float-transformer](#) (Float Transformer) resolves float
content not requiring external tools. [csu:external-render-handler](#) (External Render Handler) coordinates
parallel subprocess rendering via luv. [csu:object-render-handler](#) (Object Render Handler) invokes type-specific
header/body renderers. [csu:specification-render-handler](#) (Specification Render Handler) renders document title
headers. [csu:relation-link-rewriter](#) (Relation Link Rewriter) rewrites `(@)` link targets to resolved anchors
in the final AST.

[csc:emit-handlers](#) (Emit Handlers) assembles and generates output documents. [csu:fts-indexer](#) (FTS
Indexer) populates full-text search tables. [csu:float-numbering](#) (Float Numbering) assigns sequential
numbers by counter group. [csu:document-assembler](#) (Document Assembler) reconstructs complete Pandoc AST
from SpecIR. [csu:float-resolver](#) (Float Resolver) builds the rendered float lookup map. [csu:float-emitter](#)
(Float Emitter) replaces float placeholders with rendered Divs. [csu:view-emitter](#) (View Emitter)
expands view placeholders with materialized content. [csu:inline-handler-dispatcher](#) (Inline Handler Dispatcher)
processes inline elements — links, citations, math. [csu:float-handler-dispatcher](#) (Float Handler Dispatcher)
routes float rendering to type-specific handlers. [csu:view-handler-dispatcher](#) (View Handler Dispatcher) routes
view expansion to type-specific materializers. [csu:emitter-orchestrator](#) (Emitter Orchestrator) coordinates
the full emit sequence: numbering, assembly, resolution, filtering, and parallel Pandoc output.

[csc:infrastructure](#) (Infrastructure) provides cross-cutting utilities. [csu:hash-utilities](#) (Hash Utilities)
computes SHA1 hashes for cache coherency. [csu:logger](#) (Logger) implements NDJSON structured
logging. [csu:json-utilities](#) (JSON Utilities) handles JSON serialization for AST interchange.
[csu:reference-cache](#) (Reference Cache) caches resolved cross-references for O(1) lookup during emit.
[csu:mathml-to-omml-converter](#) (MathML to OMML Converter) translates MathML equations to Office Math Markup for
DOCX output.

[csc:format-utilities](#) (Format Utilities) provides format-specific helpers. [csu:format-writer](#) (Format Writer)
serializes AST to intermediate JSON for Pandoc consumption. [csu:xml-utilities](#) (XML Utilities)
generates and manipulates XML for OOXML postprocessing. [csu:zip-utilities](#) (ZIP Utilities) handles
DOCX archive creation and modification.

[csc:docx-generation](#) (DOCX Generation) produces Word documents. [csu:preset-loader](#) (Preset Loader) reads
style preset definitions from Lua files. [csu:style-builder](#) (Style Builder) generates OOXML style
elements from preset values. [csu:ooxml-builder](#) (OOXML Builder) assembles the final DOCX package
with styles, numbering, and content parts. [csu:reference-generator](#) (Reference Generator) creates
`reference.docx` for Pandoc's `--reference-doc` option.

[csc:io-utilities](#) (I/O Utilities) provides file-system operations. [csu:document-walker](#) (Document Walker)
traverses specification documents and their includes to build processing contexts. [csu:file-walker](#)
(File Walker) scans directories for files matching glob patterns during model discovery.

[csc:process-management](#) (Process Management) manages external subprocesses. [csu:pandoc-cli-builder](#) (Pandoc CLI
Builder) constructs Pandoc command-line arguments for each output format. [csu:task-runner](#) (Task
Runner) provides the luv-based parallel task executor used by both external float rendering
and batch Pandoc output generation.

```puml:fd-004-transform-emit{caption="Transform and Emit Pipeline"}
@startuml
skinparam backgroundColor #FFFFFF
skinparam sequenceMessageAlign center

participant "Pipeline\nOrchestrator" as P [CSU-006](@)
participant "Pipeline\nHandlers" as H [CSC-003](@)
participant "Data\nManager" as DB [CSU-012](@)
participant "Task\nRunner" as T [CSU-080](@)
participant "Pandoc CLI\nBuilder" as PC [CSU-079](@)

== TRANSFORM Phase ==
P -> H: [CSU-039](@)
H -> DB: UPDATE spec_floats SET number
note right: First: link display text\n("Figure 3") needs the numbers

P -> H: [CSU-061](@)
H -> DB: UPDATE spec_floats.resolved_ast

P -> H: [CSU-060](@)
H -> DB: SELECT resolved relations ([CSU-165](@))
H -> H: rewrite diagram links ([CSU-166](@))
note right: Diagram links lowered before render:\n[HLR-OUT-008](@), [DD-CORE-008](@)
H -> T: spawn_batch(plantuml -tpng && -tsvg, ...)
T --> H: results[]
H -> DB: UPDATE resolved_ast (png_paths, svg_paths)

P -> H: [CSU-162](@)
H -> DB: UPDATE object, attribute, float ASTs (rewrite links)

P -> H: [CSU-062](@)
loop for each object
    H -> H: type render hook (header + body)
    H -> DB: UPDATE spec_objects.ast
end

P -> H: [CSU-063](@)
H -> DB: UPDATE specifications.header_ast

P -> H: [CSU-114](@)
H -> DB: UPDATE ASTs (citation links to Cite)

== ANALYZE Phase ==
P -> H: [CSU-031](@)
H -> DB: SELECT verification views
note right: Errors abort before EMIT

== EMIT Phase ==
P -> H: [CSU-041](@)
H -> DB: INSERT INTO fts_objects, fts_attributes, fts_floats

P -> H: [CSU-037](@)
loop for each specification
    H -> H: assemble document ([CSU-034](@))
    H -> H: resolve and emit floats ([CSU-040](@), [CSU-035](@))
    H -> H: render views live ([CSU-036](@))
    H -> H: drop svg attribute for non-HTML,\napply format filters ([CSU-084](@))
end

H -> T: spawn_batch(pandoc tasks)
note right: Parallel output\ngeneration via luv
T -> PC: pandoc convert (docx, html5, ...)
PC --> T: output files

H -> H: run postprocessors ([CSU-125](@))
note right: Phase order: [puml:fd-001-pipeline](#)
@enduml
```

#### LLR: DOCX Preset Loader Resolves, Merges, And Validates Preset Chains @LLR-OUT-029-01

DOCX preset loading shall resolve preset paths, merge extends chains deterministically, and reject malformed or cyclic preset definitions.

> verification_method: Test

> traceability: [HLR-OUT-005](@)

#### LLR: Assembler Queries by File Sequence @LLR-070

Given a [dic:specification](#) identifier, [csu:document-assembler](#) shall query `spec_objects` ordered by `file_seq`, producing a Pandoc Block list in document order.

> verification_method: Test

> traceability: [HLR-OUT-001](@)

#### LLR: Include Header Level Adjustment @LLR-071

Given an included file under an active heading, [csu:include-handler](#) shall shift all Pandoc Header levels by the same amount. The shallowest included heading shall be one level below the active heading. The handler shall preserve relative depths and combine shifts across nested includes. A `----` section close shall reduce the active level by one. Without an active heading, the handler shall preserve source levels. The source file can start at any heading level. The handler shall preserve computed levels greater than 6.

> verification_method: Test

> traceability: [HLR-OUT-001](@)

#### LLR: Float and View Placeholder Insertion @LLR-072

Given [dic:spec-float](#) and [dic:spec-view](#) positions, [csu:document-assembler](#) shall insert [dic:placeholder-block](#)s at correct `file_seq` positions for downstream resolution.

> verification_method: Test

> traceability: [HLR-OUT-001](@)

#### LLR: Float Placeholder Label Matching @LLR-073

Given a [dic:placeholder-block](#) in the assembled document, [csu:float-emitter](#) shall match its `label` against `spec_floats` records to retrieve the `resolved_ast`.

> verification_method: Test

> traceability: [HLR-OUT-002](@)

#### LLR: Float Semantic Div Wrapping @LLR-074

Given a resolved [dic:spec-float](#), [csu:float-emitter](#) shall wrap it in a Pandoc Div with semantic classes (`speccompiler-float`, [dic:counter-group](#)-specific class) and a bookmark anchor identifier.

> verification_method: Test

> traceability: [HLR-OUT-002](@)

#### LLR: Failed Float Error Placeholder @LLR-075

Given a [dic:spec-float](#) with NULL `resolved_ast` (failed [dic:external-renderer](#)), [csu:float-emitter](#) shall preserve an error placeholder block with [dic:diagnostic-record](#) message.

> verification_method: Test

> traceability: [HLR-OUT-002](@)

#### LLR: Monotonic Float Numbering @LLR-076

Given all [dic:spec-float](#)s across all [dic:specification](#)s ordered by `file_seq`, [csu:float-numbering](#) shall assign monotonically increasing `number` within each [dic:counter-group](#), starting at 1.

> verification_method: Test

> traceability: [HLR-OUT-003](@)

#### LLR: Shared Counter Group Numbering @LLR-077

When float types share a [dic:counter-group](#) (e.g., FIGURE, CHART, PLANTUML share "FIGURE"), [csu:float-numbering](#) shall use a single numbering sequence.

> verification_method: Test

> traceability: [HLR-OUT-003](@)

#### LLR: Output Cache Skip @LLR-078

Given an assembled Pandoc document and output config, [csu:emitter-orchestrator](#) shall call [csu:output-cache](#) `is_output_current()` and skip format generation when it returns `true`.

> verification_method: Test

> traceability: [HLR-OUT-004](@)

#### LLR: Intermediate JSON Cleanup @LLR-079

After Pandoc format conversion completes, [csu:emitter-orchestrator](#) shall remove the intermediate JSON file from the build directory.

> verification_method: Test

> traceability: [HLR-OUT-004](@)

#### LLR: HTML5 Resource Embedding @LLR-080

When `embed_resources: true` is set in project.yaml `html5:` config, [csu:pandoc-cli-builder](#) shall add `--embed-resources` to Pandoc CLI args, producing single-file HTML5 output.

> verification_method: Test

> traceability: [HLR-OUT-006](@)

#### LLR: HTML5 Search Index Bundling @LLR-081

When [dic:full-text-search](#) tables are populated, [csu:html5-postprocessor](#) HTML5 postprocessor shall bundle the search index JSON into the output.

> verification_method: Test

> traceability: [HLR-OUT-006](@)

#### LLR: FTS5 Table Creation with Porter Stemming @LLR-082

During [dic:emit-phase](#) phase, [csu:fts-indexer](#) shall create FTS5 virtual tables (`fts_objects`, `fts_attributes`, `fts_floats`) with `tokenize='porter'`.

> verification_method: Test

> traceability: [HLR-OUT-007](@)

#### LLR: AST to Plain Text for FTS Indexing @LLR-083

Given [dic:spec-object](#) body [dic:abstract-syntax-tree](#), [csu:fts-indexer](#) shall convert to plain text via Pandoc `utils.stringify()` before inserting into the [dic:full-text-search](#) index.

> verification_method: Test

> traceability: [HLR-OUT-007](@)

#### LLR: Diagram Source Link Registration @LLR-OUT-013-01

Given a [dic:spec-float](#) whose type resolves a `format_link` hook through its `extends` chain and that has a parent object, [csu:relation-parser](#) shall scan the float's raw source with [csu:source-links](#). It shall insert one `spec_relations` row per distinct (selector, link text) pair, with the parent object as source, a NULL source attribute, the float's source file, and a link line equal to the fence line plus the link's 1-based line within the content. A link matches only when its text contains no bracket or newline and its selector starts with `@` or `#`. A link preceded by `~` (PlantUML's escape) is literal text and shall not match. When the type also resolves a `mask_comments` hook, the scan shall run on its result, so links inside the diagram tool's comments are not registered, as Markdown ignores links in HTML comments. Floats without a parent object shall be skipped.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

#### LLR: Diagram Link Lowering Before Render @LLR-OUT-013-02

Given a float whose type declares `format_link`, [csu:external-render-handler](#) shall run after float numbering. Before calling `prepare_task`, it shall replace each link in the float source with the return value of `format_link`. The hook receives `subject.href` and `subject.display_text` from [csu:relation-lookup](#), the same lookup that [csu:relation-link-rewriter](#) uses for body links. Same-document targets are `#anchor`, and cross-document targets are `{spec}.ext#anchor`. An unresolved `@` or `#` link shall fall back to the base-selector target and keep the authored text. A link with an extended selector that has no fallback (citations) shall stay verbatim. `prepare_task` shall receive the rewritten source, so the content-addressed render cache keys on the resolved targets and display text.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

#### LLR: PlantUML Hyperlink Syntax and Dual Rendition @LLR-OUT-013-03

[csu:plantuml-float-type](#) shall implement `format_link` as `[[href{text} text]]`, with `[`, `]`, `{`, and `}` removed from the display text, `\` replaced by `/`, and spaces in the href encoded as `%20`. It shall implement `mask_comments` by blanking `'` line comments and `/' ... '/` block comments while keeping every newline. It shall render the source to PNG and then to SVG in one task whose `output_path` is the SVG, so a cache hit means both renditions exist and build directories from PNG-only versions re-render once. Its `resolved_ast` shall record `png_paths` and `svg_paths`.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

#### LLR: Inline SVG in HTML5 Output @LLR-OUT-013-04

Given an image float result with `svg_paths`, [csu:float-resolver](#) shall pass the SVG paths to [csu:float-emitter](#). The emitter shall add an `svg` attribute holding the SVG path under the build directory to the PNG image, keeping the float's block structure unchanged. [csu:html-filter](#) shall replace that image with the inline `<svg>` markup. It shall strip the XML prolog and doctype, add class `speccompiler-diagram` to the root element, drop the renderer's fixed size, and write the float's `width`/`height` into the root's inline style. It shall rewrite `.ext#` hrefs to `.html#` and remove `target="_top"` and `xlink:show="new"`. When the SVG file cannot be read, the filter shall keep the PNG image.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

#### LLR: Web Application Intercepts Diagram Anchors @LLR-OUT-013-05

The cross-document click handler of the single-page web application (`models/default/html/js/sidebar.js`) shall find the clicked anchor with `closest('a')`, read its `href` or `xlink:href` attribute, and decode the document id with `decodeURIComponent`. An `<a>` inside an inline SVG shall therefore navigate between specifications like a body link.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

#### LLR: Non-HTML Formats Keep the PNG Rendition @LLR-OUT-013-06

For every output format other than HTML, [csu:emitter-orchestrator](#) shall remove the image's `svg` attribute before the format filter runs. DOCX, LaTeX, Markdown, and JSON output, and every model filter, therefore see the same image element as before the feature. The float renders as the PNG image, which shows the resolved display text.

> verification_method: Test

> traceability: [HLR-OUT-008](@)

---

### DD: NDJSON Logging @DD-INFRA-001

Selected Newline-Delimited JSON format for structured logging.


> rationale: NDJSON enables:
>
> - Machine-parseable log output for CI/CD integration
> - Structured data (level, message, timestamp, context)
> - Easy filtering and analysis with standard tools (jq)
> - Human-readable when formatted
>
> Configuration via `config.logging.level` with env override `SPECCOMPILER_LOG_LEVEL`.

---

### DD: Parallel Task Execution @DD-INFRA-002

Selected luv (libuv) for parallel subprocess execution.


> rationale: Document processing benefits from parallel execution:
>
> - External renderers (PlantUML, ECharts) run concurrently
> - Pandoc output generation runs in parallel for multiple formats
> - luv provides cross-platform async I/O without external dependencies

---

### DD: Preset-Based DOCX Styles @DD-INFRA-003

Selected preset system for DOCX style customization.


> rationale: Corporate documents require consistent styling. The preset system:
>
> - Loads style definitions from Lua files
> - Generates reference.docx with custom styles
> - Caches generated reference based on preset hash
> - Enables style changes without modifying source documents

---

### DD: Deno Runtime for External Tools @DD-TOOLS-001

Selected Deno as the runtime for TypeScript-based external tools.


> rationale: Deno provides:
>
> - Single-file TypeScript execution without build step
> - Built-in npm module support via `npm:` specifiers
> - Permission-based security model
> - Cross-platform compatibility
>
> Tools are spawned via `task_runner.spawn_sync()` with timeout handling.

---

### DD: Pandoc as Document Processing Engine @DD-CORE-005

Selected Pandoc as the document parsing and output generation engine.

> rationale: Pandoc serves as both input parser and output generator:
>
> - CommonMark+extensions parsing via `pandoc.read()` provides a well-defined AST
> - Lua filter API enables in-process AST manipulation without subprocess overhead for parsing
> - Multi-format output (DOCX, HTML5, Markdown, LaTeX/PDF, JSON) from a single intermediate representation
> - `--reference-doc` support enables DOCX style customization via generated reference.docx
> - `--lua-filter` support enables format-specific transformations (docx.lua, html.lua)
> - Native bibliography support (--bibliography, --csl) for citation processing
> - Broad ecosystem adoption provides stability and community support

---

### DD: Diagram Links Lowered to Native Hyperlink Syntax @DD-CORE-008

Selected CommonSpec link syntax in diagram source, resolved by the relation infrastructure and lowered into the diagram tool's native hyperlink syntax before rendering, with dual SVG and PNG output.

> rationale: One link syntax and one relation path for body text and diagrams:
>
> - Authors write the same `[Target](@)` / `[prefix:label](#)` syntax inside a diagram float. The links are stored as ordinary relations of the float's parent object, so resolution, type inference, display text, cross-document targets, `unresolved_relation` diagnostics, and traceability are identical to body links
> - A float type opts in by declaring the `format_link` data hook. The host learns nothing diagram-specific, and a model can add the behaviour to another source-based float type
> - Lowering happens before the render, so the diagram tool lays out the resolved display text ("Figure 3", "b: Remote"). The PNG shows the same text, and the content-addressed render cache invalidates when a target or display text changes
> - Links inside the diagram tool's comments are ignored, through the optional `mask_comments` hook, as Markdown ignores links in HTML comments. Text that only looks like a link is escaped with PlantUML's own `~`, so authors keep an opt-out without a new attribute
> - The SVG path travels as an attribute of the PNG image, and the emitter strips it for non-HTML formats. Model filters for every other format see the pre-feature document unchanged
> - The render task writes the SVG last and the cache checks the SVG. A cache hit then means both renditions exist, and build directories from PNG-only versions re-render once
> - The only SVG post-processing at HTML emit is layout-safe: href `.ext` to `.html`, removal of `target`/`xlink:show`, and sizing. The SVG is inlined because links in an `<img>` never fire, `--embed-resources` turns SVG images into `data:` URIs, and `<object>` resolves `#anchor` against the SVG file
> - Consequence: a diagram link counts for type-agnostic traceability checks exactly like a body link (e.g. `traceability_csu_to_fd` counts any FD to CSU relation). Provenance stays recoverable from `from_file` and `link_line`, which fall inside the float's lines
> - Alternative of PlantUML-native links written by the author (`[[#REQ-001]]`) rejected: it bypasses the relation infrastructure (no resolution, validation, diagnostics, display text, cross-document `.ext` targets, or traceability) and differs from CommonSpec syntax
> - Alternative of post-processing the generated SVG (wrapping `[X](@)` text nodes in `<a>`) rejected: PlantUML sizes the literal Markdown text, so replacing it with the display text misaligns or overflows the layout. The text is split across `<text>` elements, Creole markup, and wrapped lines. PNG, DOCX, and LaTeX would show the raw link syntax, and the approach breaks when PlantUML's SVG output changes. Its only advantage, a render independent of resolution, does not outweigh these costs
> - Alternative of EMIT-time href injection through placeholder URLs rejected for now: the display text must be known before layout anyway, and body links are also resolved at TRANSFORM, so cached specifications have the same staleness semantics as Markdown
> - Alternative of a new relation type (e.g. `DIAGRAM_REF`) rejected: relation types encode what a link means (the selector, source attribute, source type, and target type used by inference), not where it was written. No inference dimension distinguishes a diagram, so the type would need a fake source attribute or selector. It would lose the `XREF_FIGURE`/`XREF_SEC` display text, could not cover both the `@` and `#` resolvers, and gives traceability consumers nothing
> - Alternative of a marker Div wrapping the PNG paragraph rejected: it changes the float's block structure for every format. It broke the ACM LaTeX filter, which pairs the caption Div with the `Para[Image]` beside it to build `figure*`, `\caption`, and `\label`, and it leaked into gfm and commonmark output
> - Alternative of caching on the PNG rejected: a build directory from a PNG-only version would count as a hit, so diagrams without links would never gain an SVG until a clean build
> - Alternative of SVG-only output rejected: DOCX SVG embedding needs `rsvg-convert` for its raster fallback, which the image does not ship, and LaTeX models cannot `\includegraphics` an SVG. The cost of dual output is two PlantUML runs per changed diagram, still parallel across diagrams
