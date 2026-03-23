## Pipeline Verification Cases

### VC: Five-Phase Lifecycle @VC-001

Verify that the [dic:pipeline](#) executes all five phases in correct order.

> objective: Confirm [dic:initialize-phase](#), [dic:analyze-phase](#), [dic:transform-phase](#), [dic:verify-phase](#), [dic:emit-phase](#) execute sequentially

> verification_method: Test

> approach:
> - Register handlers for all 5 phases that record execution timestamps
> - Execute pipeline with test document
> - Verify timestamps show strict ordering

> pass_criteria:
> - All 5 phases execute for every document
> - Phase order is always INITIALIZE < ANALYZE < TRANSFORM < VERIFY < EMIT

> traceability: [HLR-PIPE-001](@), [LLR-020](@), [LLR-021](@), [LLR-022](@)


### VC: Handler Registration @VC-002

Verify that [dic:handler](#) are registered with required fields.

> objective: Confirm handler registration validates name and [dic:prerequisites](#)

> verification_method: Test

> approach:
> - Attempt to register handler without name field
> - Attempt to register handler without prerequisites field
> - Attempt to register duplicate handler
> - Verify each case throws appropriate error

> pass_criteria:
> - Missing name throws "Handler must have a 'name' field"
> - Missing prerequisites throws "Handler must have a 'prerequisites' field"
> - Duplicate name throws "Handler already registered"

> traceability: [HLR-PIPE-002](@), [LLR-PIPE-002-01](@), [LLR-PIPE-002-02](@), [LLR-PIPE-002-03](@)


### VC: Topological Ordering @VC-003

Verify [dic:handler](#) execute in dependency order.

> objective: Confirm [dic:topological-sort](#) produces correct execution order

> verification_method: Test

> approach:
> - Register handlers A, B, C where B depends on A, C depends on B
> - Execute phase and record execution order
> - Verify order is A, B, C

> pass_criteria:
> - Handlers execute after all prerequisites complete
> - Alphabetical tiebreaker when multiple handlers have same in-degree
> - Cycle detection reports error

> traceability: [HLR-PIPE-003](@), [LLR-023](@), [LLR-024](@), [LLR-025](@)


### VC: Phase Abort on Errors @VC-004

Verify pipeline stops before EMIT if errors exist.

> objective: Confirm EMIT is skipped when verification fails

> verification_method: Test

> approach:
> - Create document with validation errors (missing required attribute)
> - Execute pipeline
> - Verify EMIT handlers are not invoked after VERIFY errors are reported

> pass_criteria:
> - diagnostics.has_errors() returns true after VERIFY
> - TRANSFORM phase has already completed before VERIFY
> - EMIT phase handlers never called

> traceability: [HLR-PIPE-004](@), [LLR-026](@), [LLR-027](@)


### VC: Batch Dispatch Across All Phases @VC-005

Verify that every phase uses batch-dispatched `on_{phase}` hooks.

> objective: Confirm each handler hook receives the full contexts array for INITIALIZE, ANALYZE, TRANSFORM, VERIFY, and EMIT

> verification_method: Test

> approach:
> - Create 3 test documents
> - Register handler with `on_initialize`, `on_analyze`, `on_transform`, `on_verify`, and `on_emit` hooks that record call counts and context sizes
> - Execute pipeline
> - Verify each phase hook receives array with 3 contexts

> pass_criteria:
> - Each `on_{phase}` hook is called exactly once per phase
> - Every hook receives the full contexts array
> - No `on_{phase}_batch` hooks are required

> traceability: [HLR-PIPE-005](@), [LLR-028](@), [LLR-029](@)


### VC: Context Propagation @VC-006

Verify context object contains required fields.

> objective: Confirm handlers receive complete context

> verification_method: Inspection

> approach:
> - Examine context creation in pipeline.execute()
> - Verify all documented fields are populated
> - Check context passed to each handler

> pass_criteria:
> - context.doc contains DocumentWalker instance
> - context.spec_id contains document identifier
> - context.config contains preset configuration
> - context.output_format contains primary format
> - context.outputs contains format/path pairs

> traceability: [HLR-PIPE-006](@), [LLR-PIPE-006-01](@), [LLR-PIPE-006-02](@), [LLR-PIPE-006-03](@)


### VC: Sourcepos Normalization @VC-PIPE-007

Verify inline tracking spans are stripped from AST while preserving block-level data-pos.

> objective: Confirm that Pandoc sourcepos tracking spans (data-pos, wrapper attributes) are removed from inline content across all container types while Link elements receive transferred data-pos for diagnostic reporting.

> verification_method: Test

> approach:
> - Process test document with bold, italic, and linked text that generates tracking spans
> - Execute pipeline through all five phases with JSON output
> - Oracle verifies no tracking spans remain, text content preserved, adjacent Str tokens merged

> pass_criteria:
> - No inline tracking spans with data-pos remain in output AST
> - Text content (bold, italic) preserved without wrapper spans
> - Adjacent Str tokens merged after span removal
> - Block-level data-pos attributes preserved for diagnostics

> traceability: [HLR-PIPE-007](@), [LLR-030](@), [LLR-031](@), [LLR-032](@), [LLR-033](@), [LLR-034](@), [LLR-035](@)


### VC: CommonSpec Input Parsing @VC-PIPE-008

Verify that each [dic:commonspec](#) annotation type produces the correct [dic:intermediate-representation](#) record.

> objective: Confirm that H1 headers, H2-H6 headers, blockquote attributes, fenced code blocks, Markdown links, and inline code are lowered into the correct SpecIR content tables

> verification_method: Test

> approach:
> - Process a test document containing all six annotation types
> - Query each content table (specifications, spec_objects, spec_floats, spec_attribute_values, spec_relations, spec_views)
> - Verify correct record count and field values for each annotation type

> pass_criteria:
> - H1 headers produce exactly one `specifications` record with correct type_ref and pid
> - H2-H6 headers produce `spec_objects` records with correct type inference (explicit, implicit alias, default)
> - Blockquote lines produce `spec_attribute_values` records with correct name, value, and datatype
> - Fenced code blocks with type class produce `spec_floats` records with correct type_ref and raw_content
> - Links with `(@)` targets produce `spec_relations` records with correct target_text
> - Inline code with `type:` prefix produces `spec_views` records with correct view_type_ref

> traceability: [HLR-PIPE-007](@), [LLR-030](@), [LLR-031](@), [LLR-032](@), [LLR-033](@), [LLR-034](@), [LLR-035](@)


### VC: Include File Expansion @VC-PIPE-009

Verify that `.include` code blocks are expanded with correct content and that circular includes are detected.

> objective: Confirm recursive include expansion, path resolution, and cycle detection

> verification_method: Test

> approach:
> - Create a document with nested includes (A includes B, B includes C)
> - Execute pipeline and verify all three files' content appears in the specification
> - Create a circular include and verify error is reported
> - Verify include paths resolve relative to the including file's directory

> pass_criteria:
> - Content from all included files appears in correct document order
> - Include paths resolve relative to the including file, not the project root
> - Circular includes produce a diagnostic error
> - Source position tracking attributes are present on included content

> traceability: [HLR-PIPE-008](@), [LLR-036](@), [LLR-037](@), [LLR-038](@)


### VC: PID Auto-Generation @VC-PIPE-010

Verify that spec objects without explicit `@PID` receive auto-generated PIDs.

> objective: Confirm PID generation format, collision avoidance, and composite hierarchy

> verification_method: Test

> approach:
> - Create a document with typed objects lacking `@PID` annotations
> - Execute pipeline through ANALYZE phase
> - Query `spec_objects.pid` values and verify format matches type definition
> - Create a document with both explicit and auto-generated PIDs; verify no collisions

> pass_criteria:
> - Auto-generated PIDs match the type's `pid_prefix` and `pid_format` (e.g., "HLR-001")
> - [dic:composite-object-type](#) objects receive hierarchical PIDs (e.g., "SRS-sec1.2")
> - Explicit `@PID` annotations are never overwritten
> - No duplicate PIDs exist across all specifications

> traceability: [HLR-PIPE-009](@), [LLR-039](@), [LLR-040](@), [LLR-041](@), [LLR-042](@)


### VC: Relation Type Inference @VC-PIPE-011

Verify that relations are resolved with correct type inference and [dic:specificity-scoring](#) scoring.

> objective: Confirm constraint-based matching, same-spec preference, and ambiguity detection

> verification_method: Test

> approach:
> - Create documents with relations matching different specificity levels
> - Execute pipeline through ANALYZE phase
> - Query `spec_relations` for resolved `type_ref` and `target_ref` values
> - Create an ambiguous case (two types with equal specificity) and verify ambiguity flag

> pass_criteria:
> - Relations resolve to the most specific matching type (highest constraint score)
> - Same-specification targets are preferred over cross-specification targets
> - Ambiguous relations (tied specificity) have `is_ambiguous = 1`
> - Unresolved relations have `is_unresolved = 1` with NULL target_ref

> traceability: [HLR-PIPE-010](@), [LLR-043](@), [LLR-044](@), [LLR-045](@), [LLR-046](@)
