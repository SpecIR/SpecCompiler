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


### VC: Handler Registration Interface @VC-021

Verify type modules can export handlers.

> objective: Confirm M.handler is registered with pipeline

> verification_method: Test

> approach:
> - Create type module with M.handler export
> - Load model
> - Verify handler is registered in pipeline

> pass_criteria:
> - Handler registered if M.handler exists
> - Handler prerequisites respected
> - Handler invoked during appropriate phase

> traceability: [HLR-EXT-003](@), [LLR-EXT-021-01](@), [LLR-EXT-021-02](@)


### VC: Type Definition Schema @VC-022

Verify type modules follow required schema.

> objective: Confirm type exports contain required fields

> verification_method: Test

> approach:
> - Create valid and invalid type modules in a temporary model
> - Load model through TypeLoader.load_model()
> - Verify valid schemas register with defaults and invalid schemas are ignored

> pass_criteria:
> - Valid types are inserted into category tables
> - Missing-id schemas are skipped
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

> objective: Confirm that data view modules in models/{model}/types/views/ are discovered and their generate() function produces data for chart consumers.

> verification_method: Inspection

> approach:
> - Examine data_loader.load_view() resolution logic (model-first, default fallback)
> - Verify generate(params, data) receives user parameters and DataManager instance
> - Confirm returned dataset is passed to chart float rendering

> pass_criteria:
> - View modules loaded from models/{model}/types/views/
> - Resolution tries specified model first, falls back to default
> - generate() receives params table and DataManager instance
> - Return value used as chart data source

> traceability: [HLR-EXT-007](@), [LLR-095](@)


### VC: Handler Caching @VC-026

Verify type handler loaders cache modules to avoid repeated loading.

> objective: Confirm handler dispatchers maintain a cache keyed by model and type_ref, including negative caching for missing handlers.

> verification_method: Inspection

> approach:
> - Examine float_handlers, view_handlers, and inline_handlers dispatch modules
> - Verify cache keyed by {model}:{type_ref}
> - Confirm cache hit returns stored handler without re-loading
> - Confirm failed lookups store false to prevent repeated require() calls

> pass_criteria:
> - Cache keyed by model:type_ref combination
> - Second access to same type returns cached handler
> - Failed lookup stores false (negative cache)
> - No repeated require() for previously loaded types

> traceability: [HLR-EXT-008](@), [LLR-096](@)


### VC: Canonical Hook Context @VC-EXT-009

Verify every plugin hook receives a single frozen context whose invariant core is non-nil, and that the two context tiers are dispatched by hook name.

> objective: Confirm `contract.ctx` / `hook_ctx` build a frozen context that is the SOLE argument to every hook -- a render ctx (pandoc/format present) for render-tier hooks and a data ctx for data-tier hooks -- with the invariant core asserted non-nil.

> verification_method: Test

> approach:
> - Build a model whose object/view/float/relation/verification hooks read `ctx.subject.*` and core fields
> - Assert `ctx.new` / `ctx.new_data` reject a missing invariant-core field at build time
> - Exercise a render hook (render ctx: data, pandoc, log, format, spec_id, model, config, host) and a data hook (data ctx: data, spec_id, log)
> - Confirm `ctx:require(field)` raises on nil

> pass_criteria:
> - Every hook is invoked with exactly one frozen context table; writes to it error
> - Render-tier hooks (render/render_block/render_link/message) receive the render ctx; data-tier hooks (dataset/build_block/transform/resolve/prepare_task/handle_result) receive the data ctx
> - A missing required core field is a loud build-time error, not a silent nil
> - The hook name selects the tier (registry ALLOWED_HOOKS); a hook in the wrong tier is rejected at registration

> traceability: [HLR-EXT-009](@)


### VC: Model Manifest @VC-EXT-010

Verify each in-tree model carries a `model.yaml` declaring its overlay chain and that only repo-bundled models load.

> objective: Confirm `model.yaml` (`name`, `description`, `extends`, `requires`) is read and the declared overlay chain (default then template, later-wins-by-id) is honoured, with no out-of-tree search path.

> verification_method: Test

> approach:
> - Load a model whose `model.yaml` sets `extends: [default]`
> - Verify the host overlays default then the model, later-wins-by-id
> - Confirm a requested model with no directory is a loud error

> pass_criteria:
> - `model.yaml` is parsed and the overlay order matches `extends`
> - Models resolve only under `models/<name>/`; no registry/package-manager lookup
> - A fully-absent requested model aborts loudly

> traceability: [HLR-EXT-010](@)


### VC: Descriptor and Role Inference @VC-EXT-011

Verify a plugin returns one `{kind, schema, hooks}` descriptor and that role/hook validation is enforced at registration.

> objective: Confirm the host registers one descriptor per file, indexes its `hooks` by name into the `(kind,id)->hook` index, infers role from the hooks present, and rejects malformed descriptors loudly.

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


### VC: Verification Descriptor @VC-EXT-012

Verify a verification view is a `kind="verification"` descriptor forwarded to the host's ordered policy_key registry with override and disabled semantics.

> objective: Confirm `{schema = {policy_key, view, sql, disabled}, hooks = {message}}` descriptors feed the ordered registry, that a later model overrides an earlier policy_key in place, and that `disabled=true` removes it.

> verification_method: Test

> approach:
> - Register two verification descriptors with the same `policy_key` from different models; confirm later-wins, in place
> - Register one with `disabled=true`; confirm it is removed
> - Run the verify phase and confirm each active view emits its `message`

> pass_criteria:
> - Verification descriptors register through the same `as_descriptor` path as type modules
> - policy_key override preserves ordering; disabled removes the entry
> - The verify phase emits diagnostics via the descriptor's `message` hook

> traceability: [HLR-EXT-012](@)


### VC: Manifest-Only Configuration @VC-CFG-001

Verify all build configuration comes from `project.yaml` read once into a frozen config slice, with env reads limited to toolchain bootstrap and terminal autodetect.

> objective: Confirm `config.lua` reads `project.yaml` once into a frozen slice and that the former config-leak env reads (`OUTPUT_FORMAT`, `BUILD_DIR`, `SPECCOMPILER_LOG_LEVEL`) are gone.

> verification_method: Analysis

> approach:
> - Static review of `src/core/config.lua`: configuration is sourced from the manifest, not the environment
> - Grep the codebase for `os.getenv`; confirm only `SPECCOMPILER_HOME`/`SPECCOMPILER_DIST` (bootstrap) and `TERM`/`CI`/`NO_COLOR`/`NUMBER_OF_PROCESSORS` (autodetect) remain
> - Confirm the config slice threaded onto `ctx.config` is frozen

> pass_criteria:
> - No `os.getenv` read sources a build configuration value
> - `project.yaml` is authoritative; the config slice is read once and frozen
> - Toolchain/terminal env reads are the only survivors

> traceability: [HLR-CFG-001](@)
