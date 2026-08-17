## Extension Verification Cases

### VC: Model Type Loading @VC-019

Verify [dic:type-loader](#) discovers and loads model types.

> objective: Confirm types from models/{model}/types/ are registered

> verification_method: Test

> approach:
> - Create test model with object, float, relation types
> - Call TypeLoader.load_model()
> - Query type tables for registered types

> pass_criteria:
> - All .lua files in types/ directories are loaded
> - Type definitions inserted into correct tables
> - Errors logged for invalid type modules

> traceability: [HLR-EXT-001](@), [LLR-094](@)


### VC: Model Directory Structure @VC-020

Verify [dic:type-loader](#) recognizes all type categories.

> objective: Confirm KNOWN_CATEGORIES are all scanned

> verification_method: Test

> approach:
> - Examine TypeLoader.KNOWN_CATEGORIES constant
> - Create types in each category directory
> - Verify all are loaded

> pass_criteria:
> - specifications/ types load to spec_specification_types
> - objects/ types load to spec_object_types
> - floats/ types load to spec_float_types
> - relations/ types load to spec_relation_types
> - views/ types load to spec_view_types

> traceability: [HLR-EXT-002](@), [LLR-EXT-020-01](@)


### VC: Descriptor Registration @VC-021

Verify that the host registers descriptor hooks.

> objective: Confirm the host indexes behavior hooks and registers phase hooks with the pipeline.

> verification_method: Test

> approach:
> - Create a descriptor with a behavior hook and an `on_<phase>` hook
> - Load the model
> - Inspect the host hook index and pipeline handlers

> pass_criteria:
> - The behavior hook is available from the host index
> - The phase hook is registered under the derived handler name
> - `schema.phase_prerequisites` controls handler order

> traceability: [HLR-EXT-003](@), [LLR-EXT-021-01](@), [LLR-EXT-021-02](@)


### VC: Type Definition Schema @VC-022

Verify type modules follow required schema.

> objective: Confirm descriptor schemas contain the required fields.

> verification_method: Test

> approach:
> - Create valid and invalid type modules in a temporary model
> - Load model through TypeLoader.load_model()
> - Verify that valid schemas register and invalid schemas stop model loading

> pass_criteria:
> - Valid types are inserted into category tables
> - A missing `schema.id` stops model loading
> - Category defaults are applied (for example float long_name/counter_group)
> - Enum attribute values are persisted

> traceability: [HLR-EXT-004](@), [LLR-EXT-022-01](@)


### VC: Model Path Resolution @VC-023

Verify model paths resolve correctly.

> objective: Confirm SPECCOMPILER_HOME and project root are checked

> verification_method: Test

> approach:
> - Set SPECCOMPILER_HOME to custom directory with model
> - Call TypeLoader.load_model() with model present in both home and cwd
> - Verify model found in SPECCOMPILER_HOME

> pass_criteria:
> - SPECCOMPILER_HOME/models/{model}/ checked first
> - Project root models/{model}/ checked second
> - Error if model not found in either location

> traceability: [HLR-EXT-005](@), [LLR-EXT-023-01](@), [LLR-EXT-023-02](@)


### VC: External Renderer Registration @VC-024

Verify float types can declare external rendering needs.

> objective: Confirm chart/renderer integration executes and injects view data via
> `core.data_loader` before rendering.

> verification_method: Test

> approach:
> - Process markdown chart blocks with `view=...` attributes
> - Verify model fallback (`model=sw_docs` -> default `gauss`) is applied
> - Verify dataset and sankey injection paths mutate chart JSON before render
> - Verify invalid/missing views preserve original chart config while rendering continues
> - Verify no-view and unknown-view-result paths return unchanged config without aborting EMIT

> pass_criteria:
> - Floats with needs_external_render are queued for rendering
> - External tools (PlantUML, ECharts) are invoked
> - `view` data is injected into chart config for standard dataset and sankey flows
> - Missing/invalid views do not abort render and leave input config intact
> - Omitted `view` attributes preserve chart config with no injection side effects

> traceability: [HLR-EXT-006](@), [LLR-EXT-024-01](@), [LLR-EXT-024-02](@), [LLR-EXT-024-03](@)


### VC: Data View Generator Loading @VC-025

Verify [dic:data-view](#) generators are loaded from model directories and injected into chart rendering.

> objective: Confirm that data view modules in models/{model}/types/views/ are discovered and their data hooks produce data for chart and table consumers.

> verification_method: Test

> approach:
> - Examine data_loader.load_view() resolution logic (host `dataset` hook index,
>   loose-module fallback for fixture views)
> - Verify data hooks receive the frozen DATA ctx (dctx.subject.params, dctx.data)
> - Confirm returned dataset is passed to chart float rendering
> - Verify inline view params reach table-view `build_block` hooks
>   (e.g., `allocation_matrix: status=complete` filters to complete chains)

> pass_criteria:
> - View modules loaded from models/{model}/types/views/
> - Resolution uses the host hook index (default overlaid by template model)
> - Data hooks receive dctx with subject.params and data (DataManager)
> - Return value used as chart data source
> - `allocation_matrix: status=` filters the allocation chain rows (inline
>   view params delivered end-to-end)

> traceability: [HLR-EXT-007](@), [LLR-095](@)


### VC: Hook Index @VC-026

Verify that the host indexes hooks for deterministic dispatch.

> objective: Confirm hook lookup uses kind, type identifier, hook name, and the inheritance chain.

> verification_method: Inspection

> approach:
> - Register a descriptor with a behavior hook
> - Query the hook with `get_hook`
> - Register a subtype and query the hook with `get_hook_inherited`
> - Query an absent hook

> pass_criteria:
> - Direct lookup returns the registered hook
> - Inherited lookup returns the nearest hook in the `extends` chain
> - An absent hook returns nil
> - Phase hooks do not appear in the behavior-hook index

> traceability: [HLR-EXT-008](@), [LLR-096](@)

### VC: Canonical Hook Context @VC-EXT-009

Verify that each behavior hook receives one frozen context for its tier.

> objective: Confirm render hooks receive a render context and data hooks receive a data context.

> verification_method: Test

> approach:
> - Build a model whose object, view, float, relation, and analyze hooks read `ctx.subject`
> - Exercise one render hook and one data hook
> - Confirm `ctx:require(field)` raises on nil

> pass_criteria:
> - Each hook receives one frozen context table
> - Render hooks receive Pandoc and format fields
> - Data hooks receive the fields required for data processing
> - An invalid hook for the descriptor kind stops registration

> traceability: [HLR-EXT-009](@)


### VC: Model Manifest @VC-EXT-010

Verify that the host loads manifest dependencies before the selected model.

> objective: Confirm `model.yaml` dependencies define a deterministic load order.

> verification_method: Test

> approach:
> - Load a model whose `model.yaml` declares `requires: [base_model]`
> - Verify that the host loads `base_model` before the selected model
> - Request an absent model

> pass_criteria:
> - Required models load before the requesting model
> - Each model loads at most once
> - An absent selected or required model stops the build

> traceability: [HLR-EXT-010](@)


### VC: Descriptor and Hook Validation @VC-EXT-011

Verify descriptor and hook validation during registration.

> objective: Confirm the host indexes valid hooks and rejects invalid descriptors.

> verification_method: Test

> approach:
> - Register descriptors of each kind and query the host hook index
> - Register malformed descriptors: unknown kind, missing `schema.id`, a hook not valid for the kind, a top-level function key, a TABLE_VIEW subtype with no `build_block`
> - Confirm each malformed case is a register-time (or finalize-time) error

> pass_criteria:
> - A well-formed descriptor registers and its hooks are reachable via `get_hook` / `get_hook_inherited`
> - Unknown kind, missing id, and an invalid-for-kind hook each abort at registration
> - A function smuggled onto a top-level descriptor key is rejected (behavior must live in `hooks`)
> - A view extending TABLE_VIEW with no `build_block` is rejected at `finalize()`

> traceability: [HLR-EXT-011](@)


### VC: Analyze Query Descriptor @VC-EXT-012

Verify that a `kind = "analyze"` descriptor enters the ordered policy registry.

> objective: Confirm `{schema = {policy_key, view, sql, disabled}, hooks = {message}}` descriptors feed the ordered registry, that a later model overrides an earlier policy_key in place, and that `disabled=true` removes it.

> verification_method: Test

> approach:
> - Register two analyze descriptors with the same `policy_key`
> - Register an analyze descriptor with `disabled = true`
> - Run ANALYZE and inspect diagnostics from active queries

> pass_criteria:
> - Analyze descriptors use the same descriptor registration path as type modules
> - A repeated policy key replaces its entry without changing its position
> - A disabled descriptor removes its policy key
> - ANALYZE uses the descriptor's `message` hook for diagnostics

> traceability: [HLR-EXT-012](@)


### VC: Manifest-Only Configuration @VC-CFG-001

Verify that build options come from the frozen project configuration.

> objective: Confirm environment variables do not replace project build options.

> verification_method: Analysis

> approach:
> - Inspect project configuration loading
> - Inspect environment-variable reads for toolchain paths and terminal detection
> - Confirm the config slice threaded onto `ctx.config` is frozen

> pass_criteria:
> - No `os.getenv` read sources a build configuration value
> - `project.yaml` is authoritative for build options
> - The host freezes the context configuration
> - Environment reads only locate tools or detect runtime conditions

> traceability: [HLR-CFG-001](@)
