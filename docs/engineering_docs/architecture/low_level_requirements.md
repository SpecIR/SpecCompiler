## Low-Level Requirements

The following LLRs define implementation-level contracts that are directly
verified by executable tests.

### LLR: Handler Registration Requires Name @LLR-PIPE-002-01

> description: Pipeline handler registration shall reject handlers that do not
> provide a non-empty `name` field.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-002](@)

### LLR: Handler Registration Requires Prerequisites @LLR-PIPE-002-02

> description: Pipeline handler registration shall reject handlers that do not
> provide a `prerequisites` array.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-002](@)

### LLR: Duplicate Handler Names Are Rejected @LLR-PIPE-002-03

> description: Pipeline handler registration shall reject duplicate handler
> names within the same pipeline instance.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-002](@)

### LLR: Base Context Fields Are Propagated @LLR-PIPE-006-01

> description: Pipeline execution shall propagate the base context fields
> (`validation`, `build_dir`, `log`, `output_format`, `template`, `reference_doc`,
> `docx`, `project_root`, `outputs`, `html5`, `bibliography`, `csl`) to handlers.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-006](@)

### LLR: Document Context Is Attached Per Document @LLR-PIPE-006-02

> description: Pipeline execution shall attach `doc` and `spec_id` for each
> processed document context passed to handlers.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-006](@)

### LLR: Project Context Exists Without Documents @LLR-PIPE-006-03

> description: Pipeline execution shall create a fallback project context when
> the document list is empty, with `doc=nil` and a derived `spec_id`.
>
> verification_method: Test
>
> traceability: [HLR-PIPE-006](@)

### LLR: Known Type Categories Are Scanned @LLR-EXT-020-01

> description: Type loading shall scan each known category directory
> (`objects`, `floats`, `views`, `relations`, `specifications`) and register
> discovered modules.
>
> verification_method: Test
>
> traceability: [HLR-EXT-002](@)

### LLR: Exported Handlers Are Registered @LLR-EXT-021-01

> description: When a type module exports `handler`, model loading shall call
> `pipeline:register_handler(handler)` and propagate registration errors.
>
> verification_method: Test
>
> traceability: [HLR-EXT-003](@)

### LLR: Handler attr_order Controls Attribute Display Sequence @LLR-EXT-021-02

> description: When a type handler is created with an `attr_order` array in its options,
> the handler shall render attributes in the specified sequence first; any remaining
> attributes not listed in `attr_order` shall be appended alphabetically. When `attr_order`
> is absent, all attributes shall render alphabetically.
>
> verification_method: Test
>
> traceability: [HLR-EXT-003](@)

### LLR: Schemas Without Identifier Are Ignored @LLR-EXT-022-01

> description: Category registration helpers shall ignore schema tables that do
> not provide `id`; valid schemas shall receive category defaults and attribute
> enum values shall be registered.
>
> verification_method: Test
>
> traceability: [HLR-EXT-004](@)

### LLR: Model Path Resolution Order @LLR-EXT-023-01

> description: Model path resolution shall check `SPECCOMPILER_HOME/models/{model}`
> before checking `{cwd}/models/{model}`.
>
> verification_method: Test
>
> traceability: [HLR-EXT-005](@)

### LLR: Missing Model Paths Fail Fast @LLR-EXT-023-02

> description: Model loading shall raise an error when the model cannot be
> located in either `SPECCOMPILER_HOME` or project-root `models/`.
>
> verification_method: Test
>
> traceability: [HLR-EXT-005](@)

### LLR: Data Views Resolve With Default Fallback @LLR-EXT-024-01

> description: Chart data view loading shall resolve
> `models.{requested}.types.views.{view}` first and fallback to
> `models.default.types.views.{view}` when the requested model module is missing.
>
> verification_method: Test
>
> traceability: [HLR-EXT-006](@)

### LLR: Sankey Views Inject Series Data And Clear Dataset @LLR-EXT-024-02

> description: When a chart contains a `sankey` series and view output returns
> `data`/`links`, injection shall write to `series[1].data` and
> `series[1].links`, and clear `dataset` to prevent conflicts.
>
> verification_method: Test
>
> traceability: [HLR-EXT-006](@)

### LLR: DataManager Rollback Cancels Staged Inserts @LLR-DB-007-01

> description: `DataManager.begin_transaction()` followed by facade insert calls
> and `DataManager.rollback()` shall leave no persisted staged rows.
>
> verification_method: Test
>
> traceability: [HLR-STOR-001](@)

### LLR: DataManager CRUD Facade Persists Canonical IR Rows @LLR-DB-007-02

> description: DataManager facade methods (`insert_specification`,
> `insert_object`, `insert_float`, `insert_relation`, `insert_view`,
> `insert_attribute_value`, `query_all`, `query_one`, `execute`) shall persist
> and retrieve canonical IR rows in content tables.
>
> verification_method: Test
>
> traceability: [HLR-STOR-001](@)

### LLR: Attribute Casting Persists Typed Columns For Valid Pending Rows @LLR-DB-008-01

> description: Attribute casting shall map raw attribute values to the correct
> typed columns (`string_value`, `int_value`, `real_value`, `bool_value`,
> `date_value`, `enum_ref`) and skip updates for invalid casts.
>
> verification_method: Test
>
> traceability: [HLR-STOR-002](@)

### LLR: Chart Injection Leaves Config Intact For No-View Or Unsupported View Data @LLR-EXT-024-03

> description: Chart data injection shall preserve input chart configuration when
> no `view` is provided or when view output does not match supported shapes
> (`source` or `data`+`links` for sankey).
>
> verification_method: Test
>
> traceability: [HLR-EXT-006](@)

### LLR: DOCX Preset Loader Resolves, Merges, And Validates Preset Chains @LLR-OUT-029-01

> description: DOCX preset loading shall resolve preset paths, merge extends
> chains deterministically, and reject malformed or cyclic preset definitions.
>
> verification_method: Test
>
> traceability: [HLR-OUT-005](@)
