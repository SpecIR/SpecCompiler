## Pipeline Verification Cases

### VC: Five-Phase Lifecycle @VC-001

Verify that the [TERM-15](@) executes all five phases in correct order.

> objective: Confirm [TERM-19](@), [TERM-20](@), [TERM-22](@), [TERM-21](@), [TERM-23](@) execute sequentially

> verification_method: Test

> approach:
> - Register handlers for all 5 phases that record execution timestamps
> - Execute pipeline with test document
> - Verify timestamps show strict ordering

> pass_criteria:
> - All 5 phases execute for every document
> - Phase order is always INITIALIZE < ANALYZE < TRANSFORM < VERIFY < EMIT

> traceability: [HLR-PIPE-001](@)


### VC: Handler Registration @VC-002

Verify that [TERM-16](@) are registered with required fields.

> objective: Confirm handler registration validates name and [TERM-24](@)

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

Verify [TERM-16](@) execute in dependency order.

> objective: Confirm [TERM-25](@) produces correct execution order

> verification_method: Test

> approach:
> - Register handlers A, B, C where B depends on A, C depends on B
> - Execute phase and record execution order
> - Verify order is A, B, C

> pass_criteria:
> - Handlers execute after all prerequisites complete
> - Alphabetical tiebreaker when multiple handlers have same in-degree
> - Cycle detection reports error

> traceability: [HLR-PIPE-003](@)


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

> traceability: [HLR-PIPE-004](@)


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

> traceability: [HLR-PIPE-005](@)


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

> traceability: [HLR-PIPE-001](@)
