## Extension Verification Cases

### VC: Model Type Loading @VC-019

Verify [TERM-38](@) discovers and loads model types.

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

> traceability: [HLR-EXT-001](@)


### VC: Model Directory Structure @VC-020

Verify [TERM-38](@) recognizes all type categories.

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

Verify [TERM-35](@) generators are loaded from model directories and injected into chart rendering.

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

> traceability: [HLR-EXT-007](@)


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

> traceability: [HLR-EXT-008](@)
