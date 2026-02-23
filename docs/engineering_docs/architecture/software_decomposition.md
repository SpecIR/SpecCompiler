## Software Decomposition

This chapter defines decomposition and design allocation using MIL-STD-498 nomenclature:

- `CSC` ([TERM-36](@)) identifies structural subsystems/layers.
- `CSU` ([TERM-37](@)) identifies concrete implementation units.

> **Note:** Software Functions (SF) are defined in the SRS alongside their
> constituent HLRs. Functional Descriptions (FD) trace to SFs via the REALIZES
> relation and are documented in the SDD design files.

### Core Software Components

#### Core Runtime Layer

#### CSC: Core Runtime @CSC-001

> component_type: Layer

> path: src/core/

> description: Pipeline orchestration, metadata/config extraction, model loading, proof loading, validation policy, and runtime control.

##### CSU: Pandoc Filter Entry Point @CSU-001

> file_path: src/filter.lua

> language: Lua

> description: Pandoc filter entry point that hooks into Meta(meta) to extract project configuration and invoke engine.run_project(), serving as the bridge between Pandoc and the SpecCompiler build system.

> traceability: [CSC-001](@)

##### CSU: Configuration Parser @CSU-002

> file_path: src/core/config.lua

> language: Lua

> description: Parses and validates project.yaml metadata via Pandoc, extracting project configuration into plain Lua tables for consumption by the engine.

> traceability: [CSC-001](@)

##### CSU: Data Loader @CSU-003

> file_path: src/core/data_loader.lua

> language: Lua

> description: Loads view modules from models/{model}/types/views/ and invokes their generate() function to produce data for charts and other data-driven consumers.

> traceability: [CSC-001](@)

##### CSU: Diagnostics Collector @CSU-004

> file_path: src/core/diagnostics.lua

> language: Lua

> description: Collects and emits structured errors and warnings (with file, line, column, and diagnostic code) via the logger diagnostic API.

> traceability: [CSC-001](@)

##### CSU: Build Engine @CSU-005

> file_path: src/core/engine.lua

> language: Lua

> description: Main orchestrator that wires together the pipeline, database, [TERM-38](@), file walker, [TERM-30](@), and output emission to run a full SpecCompiler project build across all documents.

> traceability: [CSC-001](@)

##### CSU: Pipeline Orchestrator @CSU-006

> file_path: src/core/pipeline.lua

> language: Lua

> description: Pipeline lifecycle orchestrator that manages a 5-phase (INITIALIZE, ANALYZE, TRANSFORM, VERIFY, EMIT) execution model with declarative handler prerequisites and topological sorting.

> traceability: [CSC-001](@)

##### CSU: Proof Loader @CSU-007

> file_path: src/core/proof_loader.lua

> language: Lua

> description: Discovers, loads, and registers proof view modules from models/{model}/proofs/, maintaining an in-memory registry of proof definitions used for verification policies.

> traceability: [CSC-001](@)

##### CSU: Type Loader @CSU-008

> file_path: src/core/type_loader.lua

> language: Lua

> description: Loads type modules (objects, floats, views, relations, specifications) from models/{model}/types/ directories and populates the SpecIR type system tables in the database.

> traceability: [CSC-001](@)

##### CSU: Validation Policy @CSU-009

> file_path: src/core/validation_policy.lua

> language: Lua

> description: Manages configurable validation severity levels (error/warn/ignore) for proof codes, building default policies from loaded proof definitions and allowing project-level overrides.

> traceability: [CSC-001](@)

#### Database Persistence Layer

#### CSC: Database Persistence @CSC-002

> component_type: Layer

> path: src/db/

> description: Canonical insert/query API for SpecIR, transaction handling, build cache, output cache, and proof view definitions.

##### CSU: Build Cache @CSU-010

> file_path: src/db/build_cache.lua

> language: Lua

> description: Provides incremental build support by comparing SHA1 hashes of source documents against cached values to determine which files need rebuilding.

> traceability: [CSC-002](@)

##### CSU: Database Handler @CSU-011

> file_path: src/db/handler.lua

> language: Lua

> description: Low-level SQLite database handler that wraps lsqlite3, providing execute, query_all, and prepared statement operations for all database access.

> traceability: [CSC-002](@)

##### CSU: Data Manager @CSU-012

> file_path: src/db/manager.lua

> language: Lua

> description: High-level data manager that initializes the database schema and provides domain-specific insert/update operations for spec objects, floats, relations, and attributes.

> traceability: [CSC-002](@)

##### CSU: Output Cache @CSU-013

> file_path: src/db/output_cache.lua

> language: Lua

> description: Checks whether generated output files are up-to-date by comparing the current SpecIR state hash against the cached hash, enabling skipping of unchanged output regeneration.

> traceability: [CSC-002](@)

##### CSU: Proof View Definitions @CSU-014

> file_path: src/db/proof_views.lua

> language: Lua

> description: Defines SQL CREATE VIEW statements for all proof views used in the VERIFY phase, organized by entity type (specifications, objects, floats, relations, views).

> traceability: [CSC-002](@)

##### DB Queries Package

#### CSC: DB Queries @CSC-005

> component_type: Package

> path: src/db/queries/

> description: SQL query string modules for all database operations across content, types, build, search, and resolution domains.

##### CSU: Build Queries @CSU-015

> file_path: src/db/queries/build.lua

> language: Lua

> description: SQL query strings for build infrastructure operations: source file hash lookups, build graph (include dependency) management, and output cache entries.

> traceability: [CSC-005](@)

##### CSU: Content Queries @CSU-016

> file_path: src/db/queries/content.lua

> language: Lua

> description: SQL query strings for content-layer CRUD operations on spec_objects, spec_floats, spec_relations, spec_views, and spec_attribute_values tables.

> traceability: [CSC-005](@)

##### CSU: Query Aggregator @CSU-017

> file_path: src/db/queries/init.lua

> language: Lua

> description: Aggregation module that re-exports all domain-specific query sub-modules (types, content, search, build, resolution) under a single Queries namespace.

> traceability: [CSC-005](@)

##### CSU: Resolution Queries @CSU-018

> file_path: src/db/queries/resolution.lua

> language: Lua

> description: SQL query strings for resolving relations, float types, cross-references, and relation type inference rules using the weighted quadruple scoring system.

> traceability: [CSC-005](@)

##### CSU: Search Queries @CSU-019

> file_path: src/db/queries/search.lua

> language: Lua

> description: SQL query strings for managing FTS5 full-text search tables, including clearing, indexing, and populating fts_objects, fts_attributes, and fts_floats.

> traceability: [CSC-005](@)

##### CSU: Type Queries @CSU-020

> file_path: src/db/queries/types.lua

> language: Lua

> description: SQL query strings for inserting and querying type system metadata: float types, relation types, object types, view types, specification types, attribute types, datatype definitions, and enum values.

> traceability: [CSC-005](@)

##### DB Schema Package

#### CSC: DB Schema @CSC-006

> component_type: Package

> path: src/db/schema/

> description: DDL table creation statements for content, types, build infrastructure, and search tables.

##### CSU: Build Schema @CSU-021

> file_path: src/db/schema/build.lua

> language: Lua

> description: DDL for build infrastructure tables (build_graph, source_files, output_cache) that enable incremental builds through file dependency tracking and content hashing.

> traceability: [CSC-006](@)

##### CSU: Content Schema @CSU-022

> file_path: src/db/schema/content.lua

> language: Lua

> description: DDL for content-layer tables (specifications, spec_objects, spec_floats, spec_relations, spec_views, spec_attribute_values) that store parsed specification data.

> traceability: [CSC-006](@)

##### CSU: Schema Aggregator @CSU-023

> file_path: src/db/schema/init.lua

> language: Lua

> description: Aggregation module that combines all domain-specific schema SQL in dependency order and provides an initialize_views() entry point for post-load view creation.

> traceability: [CSC-006](@)

##### CSU: Search Schema @CSU-024

> file_path: src/db/schema/search.lua

> language: Lua

> description: DDL for FTS5 virtual tables (fts_objects, fts_attributes, fts_floats) that enable full-text search across specification content with porter stemming.

> traceability: [CSC-006](@)

##### CSU: Type System Schema @CSU-025

> file_path: src/db/schema/types.lua

> language: Lua

> description: DDL for type system (metamodel) tables (spec_object_types, spec_float_types, spec_relation_types, spec_view_types, spec_specification_types, datatype_definitions, spec_attribute_types, enum_values, implicit_type_aliases).

> traceability: [CSC-006](@)

##### DB Views Package

#### CSC: DB Views @CSC-007

> component_type: Package

> path: src/db/views/

> description: SQL view definitions for EAV pivots, public API, and resolution helpers.

##### CSU: EAV Pivot Views @CSU-026

> file_path: src/db/views/eav_pivot.lua

> language: Lua

> description: Dynamically generates per-object-type SQL views that pivot the [TERM-EAV](@) into typed columns for external BI queries (e.g., SELECT * FROM view_hlr_objects WHERE status = 'approved'). These views are not used by internal pipeline code, which queries the raw EAV tables directly. See HLR-STOR-006.

> traceability: [CSC-007](@)

##### CSU: Views Aggregator @CSU-027

> file_path: src/db/views/init.lua

> language: Lua

> description: Aggregation module that initializes all database view categories (resolution, public API, and EAV pivot) in the correct dependency order.

> traceability: [CSC-007](@)

##### CSU: Public API Views @CSU-028

> file_path: src/db/views/public_api.lua

> language: Lua

> description: Stable BI-friendly SQL views (e.g., public_traceability_matrix) intended as the public interface for external dashboards and query tools.

> traceability: [CSC-007](@)

##### CSU: Resolution Views @CSU-029

> file_path: src/db/views/resolution.lua

> language: Lua

> description: Internal SQL views for resolving float type aliases, relation types, and cross-references, moving resolution logic from Lua handler code into queryable SQL.

> traceability: [CSC-007](@)

#### Pipeline Handlers Layer

#### CSC: Pipeline Handlers @CSC-003

> component_type: Layer

> path: src/pipeline/

> description: Phase handlers implementing initialize, analyze, transform, verify, and emit behavior across five pipeline phases.

##### CSU: Include Expansion Filter @CSU-030

> file_path: src/filters/expand_includes.lua

> language: Lua

> description: Standalone Pandoc Lua filter that recursively expands include code blocks in a subprocess, outputting include dependencies to a JSON metadata file for build graph tracking.

> traceability: [CSC-003](@)

##### CSU: Verify Handler @CSU-031

> file_path: src/pipeline/verify/verify_handler.lua

> language: Lua

> description: VERIFY phase handler that iterates over all registered proof views, queries each for violations, and emits structured diagnostics based on validation policy.

> traceability: [CSC-003](@)

##### Analyze Handlers Package

#### CSC: Analyze Handlers @CSC-008

> component_type: Package

> path: src/pipeline/analyze/

> description: ANALYZE phase handlers for relation resolution, relation type inference, and attribute casting.

##### CSU: Attribute Caster @CSU-032

> file_path: src/pipeline/analyze/attribute_caster.lua

> language: Lua

> description: Casts raw attribute values to their typed columns (string, integer, real, boolean, enum, date) based on the datatype definition, returning the appropriate typed field for database storage.

> traceability: [CSC-008](@)

##### CSU: Relation Resolver @CSU-033

> file_path: src/pipeline/analyze/relation_resolver.lua

> language: Lua

> description: ANALYZE phase handler that resolves spec_relation targets by matching PIDs and header IDs across specifications, populating target_object_id and target_float_id foreign keys.

> traceability: [CSC-008](@)

##### CSU: Relation Type Inferrer @CSU-161

> file_path: src/pipeline/analyze/relation_type_inferrer.lua

> language: Lua

> description: ANALYZE phase handler that infers relation types using 4-dimension unweighted specificity scoring (selector, source_attribute, source_type, target_type) after relation_resolver has populated targets.

> traceability: [CSC-008](@)

##### Emit Handlers Package

#### CSC: Emit Handlers @CSC-009

> component_type: Package

> path: src/pipeline/emit/

> description: EMIT phase handlers for document assembly, float resolution, view rendering, FTS indexing, and output generation.

##### CSU: Document Assembler @CSU-034

> file_path: src/pipeline/emit/assembler.lua

> language: Lua

> description: Reconstructs a complete Pandoc document from the SpecIR database by querying spec_objects, spec_floats, and spec_views, decoding their stored AST JSON back into Pandoc blocks.

> traceability: [CSC-009](@)

##### CSU: Float Emitter @CSU-035

> file_path: src/pipeline/emit/emit_float.lua

> language: Lua

> description: Transforms Pandoc documents during EMIT by replacing float CodeBlock elements with their rendered content (images, tables, charts) and adding captions and bookmarks.

> traceability: [CSC-009](@)

##### CSU: View Emitter @CSU-036

> file_path: src/pipeline/emit/emit_view.lua

> language: Lua

> description: Transforms inline Code elements and standalone Code-in-Para patterns during EMIT phase, dispatching to view type handlers to produce rendered inline or block output.

> traceability: [CSC-009](@)

##### CSU: Emitter Orchestrator @CSU-037

> file_path: src/pipeline/emit/emitter.lua

> language: Lua

> description: Format-agnostic EMIT phase orchestrator that assembles the Pandoc document from IR, resolves floats, applies numbering, runs format filters and postprocessors, and writes output via Pandoc CLI.

> traceability: [CSC-009](@)

##### CSU: Float Handler Dispatcher @CSU-038

> file_path: src/pipeline/emit/float_handlers.lua

> language: Lua

> description: Model-agnostic dispatch layer that queries spec_float_types to discover and cache float handler modules, then dispatches on_render_CodeBlock calls to type-specific handlers.

> traceability: [CSC-009](@)

##### CSU: Float Numbering @CSU-039

> file_path: src/pipeline/emit/float_numbering.lua

> language: Lua

> description: Assigns sequential numbers to captioned floats per specification and per counter_group, so that related types (e.g., FIGURE, CHART, PLANTUML) share a single numbering sequence within each spec.

> traceability: [CSC-009](@)

##### CSU: Float Resolver @CSU-040

> file_path: src/pipeline/emit/float_resolver.lua

> language: Lua

> description: Collects floats with their resolved_ast and categorizes them for EMIT phase processing, distinguishing between image-producing floats and handler-dispatched floats.

> traceability: [CSC-009](@)

##### CSU: FTS Indexer @CSU-041

> file_path: src/pipeline/emit/fts_indexer.lua

> language: Lua

> description: EMIT phase handler that populates FTS5 virtual tables by converting stored Pandoc AST JSON to plain text and indexing spec objects, attributes, and floats for full-text search.

> traceability: [CSC-009](@)

##### CSU: Inline Handler Dispatcher @CSU-042

> file_path: src/pipeline/emit/inline_handlers.lua

> language: Lua

> description: Model-agnostic dispatch layer that queries spec_view_types to discover and cache inline view handler modules, then dispatches on_render_Code calls by matching inline prefixes.

> traceability: [CSC-009](@)

##### CSU: View Handler Dispatcher @CSU-043

> file_path: src/pipeline/emit/view_handlers.lua

> language: Lua

> description: Model-agnostic dispatch layer that queries spec_view_types to discover and cache block-level view handler modules, then dispatches on_render_CodeBlock calls for views.

> traceability: [CSC-009](@)

##### Initialize Handlers Package

#### CSC: Initialize Handlers @CSC-010

> component_type: Package

> path: src/pipeline/initialize/

> description: INITIALIZE phase handlers that parse document AST and populate all SpecIR container tables.

##### CSU: Attribute Parser @CSU-044

> file_path: src/pipeline/initialize/attributes.lua

> language: Lua

> description: INITIALIZE phase handler that extracts attributes from BlockQuote elements following headers, parses name: value syntax, casts values via datatype definitions, and stores them in spec_attribute_values.

> traceability: [CSC-010](@)

##### CSU: Include Handler @CSU-045

> file_path: src/pipeline/shared/include_handler.lua

> language: Lua

> description: Pre-pipeline utility that recursively expands include code blocks by reading referenced files and parsing them through Pandoc, with cycle detection and depth limiting. Called directly by the engine before pipeline execution; not a pipeline handler.

> traceability: [CSC-011](@)

##### CSU: Float Parser @CSU-046

> file_path: src/pipeline/initialize/spec_floats.lua

> language: Lua

> description: INITIALIZE phase handler that parses float CodeBlock syntax (type.lang:label{key="val"}), resolves type aliases, and stores float instances in spec_floats.

> traceability: [CSC-010](@)

##### CSU: Object Parser @CSU-047

> file_path: src/pipeline/initialize/spec_objects.lua

> language: Lua

> description: INITIALIZE phase handler that creates spec_objects rows from L2+ headers parsed by the specifications handler, inferring object types from header prefixes.

> traceability: [CSC-010](@)

##### CSU: Relation Parser @CSU-048

> file_path: src/pipeline/initialize/spec_relations.lua

> language: Lua

> description: INITIALIZE phase handler that extracts link-based relations (`[PID](@)` and `[PID](#)`) from object ASTs and stores them in spec_relations. Type inference and link rewriting are delegated to relation_type_inferrer (ANALYZE) and relation_link_rewriter (TRANSFORM).

> traceability: [CSC-010](@)

##### CSU: View Parser @CSU-049

> file_path: src/pipeline/initialize/spec_views.lua

> language: Lua

> description: INITIALIZE phase handler that registers view instances from CodeBlock and inline Code syntax, resolving view type prefixes and storing entries in spec_views.

> traceability: [CSC-010](@)

##### CSU: Specification Parser @CSU-050

> file_path: src/pipeline/initialize/specifications.lua

> language: Lua

> description: INITIALIZE phase handler that runs first to parse document headers, register the root specification from the L1 header, and store parsed header data in the pipeline context.

> traceability: [CSC-010](@)

##### Shared Pipeline Utilities Package

#### CSC: Shared Pipeline Utilities @CSC-011

> component_type: Package

> path: src/pipeline/shared/

> description: Shared infrastructure modules providing base handlers, rendering utilities, and view helpers used across pipeline phases.

##### CSU: Attribute Paragraph Utilities @CSU-051

> file_path: src/pipeline/shared/attribute_para_utils.lua

> language: Lua

> description: Shared utility functions for parsing attribute paragraphs from Pandoc inline nodes, handling Span unwrapping, text extraction, and inline content normalization.

> traceability: [CSC-011](@)

##### CSU: Float Base @CSU-052

> file_path: src/pipeline/shared/float_base.lua

> language: Lua

> description: Shared infrastructure for float type handlers, providing helper functions to update resolved_ast in the database and query floats by type and specification.

> traceability: [CSC-011](@)

##### CSU: Include Utilities @CSU-053

> file_path: src/pipeline/shared/include_utils.lua

> language: Lua

> description: Shared utility functions for identifying include directive CodeBlocks and parsing include file paths, used by both include_handler and expand_includes.

> traceability: [CSC-011](@)

##### CSU: Math Render Utilities @CSU-054

> file_path: src/pipeline/shared/math_render_utils.lua

> language: Lua

> description: Shared helpers for AsciiMath and MathML/OMML rendering, providing content hashing, script path resolution, and external process invocation for math conversion.

> traceability: [CSC-011](@)

##### CSU: Render Utilities @CSU-055

> file_path: src/pipeline/shared/render_utils.lua

> language: Lua

> description: Shared rendering utilities for spec object handlers, providing functions to add CSS classes, insert page breaks, create bookmarks, and build styled header elements.

> traceability: [CSC-011](@)

##### CSU: Source Position Compatibility @CSU-056

> file_path: src/pipeline/shared/sourcepos_compat.lua

> language: Lua

> description: Pandoc version compatibility layer that strips inline sourcepos tracking Spans from the AST while preserving line/column data on Link elements for diagnostics.

> traceability: [CSC-011](@)

##### CSU: Specification Base @CSU-057

> file_path: src/pipeline/shared/specification_base.lua

> language: Lua

> description: Shared infrastructure for specification type handlers, providing default header rendering and configurable title formatting with optional PID display.

> traceability: [CSC-011](@)

##### CSU: Spec Object Base @CSU-058

> file_path: src/pipeline/shared/spec_object_base.lua

> language: Lua

> description: Shared infrastructure for spec object type handlers (HLR, FD, VC, etc.), providing styled headers with PID prefixes, attribute display, and an extensible create_handler() factory.

> traceability: [CSC-011](@)

##### CSU: View Utilities @CSU-059

> file_path: src/pipeline/shared/view_utils.lua

> language: Lua

> description: Shared utility functions for view handlers, providing MathML-to-HTML wrapping, Pandoc element JSON serialization, and other common view rendering operations.

> traceability: [CSC-011](@)

##### Transform Handlers Package

#### CSC: Transform Handlers @CSC-012

> component_type: Package

> path: src/pipeline/transform/

> description: TRANSFORM phase handlers for view materialization, external rendering, and spec object/specification rendering.

##### CSU: External Render Handler @CSU-060

> file_path: src/pipeline/transform/external_render_handler.lua

> language: Lua

> description: TRANSFORM phase handler that orchestrates parallel rendering of external float and view types (PlantUML, charts, math) by batching tasks and dispatching to registered renderer callbacks.

> traceability: [CSC-012](@)

##### CSU: Float Transformer @CSU-061

> file_path: src/pipeline/transform/spec_floats.lua

> language: Lua

> description: TRANSFORM phase handler that resolves internal float types (TABLE, CSV, etc.) by dynamically loading type-specific modules; external floats are delegated to external_render_handler.

> traceability: [CSC-012](@)

##### CSU: Relation Link Rewriter @CSU-162

> file_path: src/pipeline/transform/relation_link_rewriter.lua

> language: Lua

> description: TRANSFORM phase handler that rewrites `@` and `#` links in stored spec_object AST JSON, replacing them with resolved anchor targets using the relation lookup built from spec_relations.

> traceability: [CSC-012](@)

##### CSU: Object Render Handler @CSU-062

> file_path: src/pipeline/transform/spec_object_render_handler.lua

> language: Lua

> description: TRANSFORM phase handler that loads object type modules and invokes their on_render_SpecObject to transform stored AST into styled output with headers, attributes, and bookmarks.

> traceability: [CSC-012](@)

##### CSU: Specification Render Handler @CSU-063

> file_path: src/pipeline/transform/specification_render_handler.lua

> language: Lua

> description: TRANSFORM phase handler that loads specification type modules and invokes their on_render_Specification to generate the document title header.

> traceability: [CSC-012](@)

##### CSU: View Materializer @CSU-064

> file_path: src/pipeline/transform/view_materializer.lua

> language: Lua

> description: TRANSFORM phase handler that pre-computes view data (TOC, traceability matrices, etc.) by querying the database and storing structured JSON in spec_views.resolved_data.

> traceability: [CSC-012](@)

#### Infrastructure Layer

#### CSC: Infrastructure @CSC-004

> component_type: Layer

> path: src/infra/

> description: Output toolchain integration, hashing, logging, JSON utilities, reference cache management, and external tool wrappers.

##### CSU: Hash Utilities @CSU-065

> file_path: src/infra/hash_utils.lua

> language: Lua

> description: Provides SHA1 hashing for content and files, using Pandoc's built-in sha1 when running inside Pandoc or falling back to a pure-Lua SHA1 implementation for standalone workers.

> traceability: [CSC-004](@)

##### CSU: JSON Utilities @CSU-066

> file_path: src/infra/json.lua

> language: Lua

> description: Unified JSON encode/decode wrapper using the dkjson pure-Lua library, providing a consistent JSON interface independent of Pandoc's JSON functions.

> traceability: [CSC-004](@)

##### CSU: Logger @CSU-067

> file_path: src/infra/logger.lua

> language: Lua

> description: TTY-aware logging system that outputs human-readable colored console messages when connected to a terminal, or structured NDJSON when piped, with configurable severity levels.

> traceability: [CSC-004](@)

##### CSU: Reference Cache @CSU-068

> file_path: src/infra/reference_cache.lua

> language: Lua

> description: Tracks whether reference.docx needs rebuilding by comparing the SHA1 hash of the preset file against a cached hash in the build_meta database table.

> traceability: [CSC-004](@)

##### CSU: MathML to OMML Converter @CSU-069

> file_path: src/tools/mathml2omml_external.lua

> language: Lua

> description: Converts MathML to Office MathML (OMML) by invoking an external Deno process running the mathml2omml npm library.

> traceability: [CSC-004](@)

##### Format Utilities Package

#### CSC: Format Utilities @CSC-013

> component_type: Package

> path: src/infra/format/

> description: Writer adapters, XML utilities, and ZIP archive operations for format-specific output generation.

##### CSU: Format Writer @CSU-070

> file_path: src/infra/format/writer.lua

> language: Lua

> description: Provides postprocessor and filter loading utilities for template-specific output modifications, discovering format-specific Lua modules from models/{template}/ directories.

> traceability: [CSC-013](@)

##### CSU: XML Utilities @CSU-071

> file_path: src/infra/format/xml.lua

> language: Lua

> description: XML utility module providing escaping, DOM construction, parsing, and manipulation via the SLAXML library for generating and transforming XML content.

> traceability: [CSC-013](@)

##### CSU: ZIP Utilities @CSU-072

> file_path: src/infra/format/zip_utils.lua

> language: Lua

> description: Cross-platform ZIP archive utilities using the lua-zip library, providing extract and create operations for DOCX archive manipulation.

> traceability: [CSC-013](@)

##### DOCX Generation Package

#### CSC: DOCX Generation @CSC-014

> component_type: Package

> path: src/infra/format/docx/

> description: OOXML builder, preset loader, reference generator, and style builder for Word document output.

##### CSU: OOXML Builder @CSU-073

> file_path: src/infra/format/docx/ooxml_builder.lua

> language: Lua

> description: Unified OOXML builder for generating Word Open XML, offering both a stateful Builder API (method chaining) and a stateless Static API (inline OOXML generation).

> traceability: [CSC-014](@)

##### CSU: Preset Loader @CSU-074

> file_path: src/infra/format/docx/preset_loader.lua

> language: Lua

> description: Loads Lua preset files that define DOCX styles, executing the preset script and returning the resulting configuration table for use by the reference generator.

> traceability: [CSC-014](@)

##### CSU: Reference Generator @CSU-075

> file_path: src/infra/format/docx/reference_generator.lua

> language: Lua

> description: Generates reference.docx by merging custom styles from preset definitions into Pandoc's default DOCX template via ZIP manipulation of the word/styles.xml file.

> traceability: [CSC-014](@)

##### CSU: Style Builder @CSU-076

> file_path: src/infra/format/docx/style_builder.lua

> language: Lua

> description: Provides unit conversion (cm/pt/in to twips) and OOXML style-building functions for generating Word paragraph and character style definitions.

> traceability: [CSC-014](@)

##### I/O Utilities Package

#### CSC: I/O Utilities @CSC-015

> component_type: Package

> path: src/infra/io/

> description: AST traversal with source position tracking and basic file I/O operations.

##### CSU: Document Walker @CSU-077

> file_path: src/infra/io/document_walker.lua

> language: Lua

> description: Provides AST traversal methods for pipeline handlers, extracting source position (line numbers) from Pandoc data-pos attributes and tracking source file provenance through include expansion.

> traceability: [CSC-015](@)

##### CSU: File Walker @CSU-078

> file_path: src/infra/io/file_walker.lua

> language: Lua

> description: Provides basic file I/O operations (read file, resolve relative paths, check existence, list directory) using luv for filesystem access.

> traceability: [CSC-015](@)

##### Process Management Package

#### CSC: Process Management @CSC-016

> component_type: Package

> path: src/infra/process/

> description: External process spawning via luv and Pandoc command-line argument building.

##### CSU: Pandoc CLI Builder @CSU-079

> file_path: src/infra/process/pandoc_cli.lua

> language: Lua

> description: Builds Pandoc command-line argument arrays from configuration, resolving filter paths and speccompiler home directory for external pandoc process invocation.

> traceability: [CSC-016](@)

##### CSU: Task Runner @CSU-080

> file_path: src/infra/process/task_runner.lua

> language: Lua

> description: Unified interface for spawning and managing external processes using luv (libuv), providing async I/O, timeouts, CPU count detection, and command existence checking.

> traceability: [CSC-016](@)

---

### Default Model Components

#### Default Model

#### CSC: Default Model @CSC-017

> component_type: Model

> path: models/default/

> description: Foundational type model providing base object, float, relation, and view types that all other models extend.

##### CSU: SECTION Object Type @CSU-081

> file_path: models/default/types/objects/section.lua

> language: Lua

> description: Defines the SECTION object type (id="SECTION"), the default type for headers without explicit TYPE: prefix; numbered, with optional XHTML description attribute.

> traceability: [CSC-017](@)

##### CSU: SPEC Specification Type @CSU-082

> file_path: models/default/types/specifications/spec.lua

> language: Lua

> description: Defines the SPEC specification type (id="SPEC"), the default type for H1 headers without explicit TYPE: prefix; title is unnumbered and does not display a PID.

> traceability: [CSC-017](@)

##### Default Filters Package

#### CSC: Default Filters @CSC-018

> component_type: Package

> path: models/default/filters/

> description: Format-specific Pandoc Lua filters that convert speccompiler markers to native output elements.

##### CSU: DOCX Filter @CSU-083

> file_path: models/default/filters/docx.lua

> language: Lua

> description: Pandoc Lua filter for DOCX output that converts speccompiler-format markers (page-break, bookmarks, math-omml, captions, equations) into native OOXML elements.

> traceability: [CSC-018](@)

##### CSU: HTML Filter @CSU-084

> file_path: models/default/filters/html.lua

> language: Lua

> description: Pandoc Lua filter for HTML5 output that converts speccompiler-format markers into semantic HTML elements with Bootstrap-compatible styling.

> traceability: [CSC-018](@)

##### CSU: Markdown Filter @CSU-085

> file_path: models/default/filters/markdown.lua

> language: Lua

> description: Pandoc Lua filter for Markdown output that converts speccompiler page-break markers to horizontal rules and removes markers with no Markdown equivalent.

> traceability: [CSC-018](@)

##### Default Postprocessors Package

#### CSC: Default Postprocessors @CSC-019

> component_type: Package

> path: models/default/postprocessors/

> description: Format-specific post-processing applied after Pandoc output generation.

##### CSU: DOCX Postprocessor @CSU-086

> file_path: models/default/postprocessors/docx.lua

> language: Lua

> description: DOCX post-processor that loads and applies template-specific OOXML post-processing to fix styles regenerated by Pandoc's DOCX writer.

> traceability: [CSC-019](@)

##### CSU: LaTeX Postprocessor @CSU-087

> file_path: models/default/postprocessors/latex.lua

> language: Lua

> description: LaTeX post-processor that loads and applies template-specific LaTeX post-processing to transform Pandoc's standard LaTeX output.

> traceability: [CSC-019](@)

##### Default Proof Views Package

#### CSC: Default Proof Views @CSC-020

> component_type: Package

> path: models/default/proofs/

> description: SQL proof view queries for detecting constraint violations across specifications, objects, floats, relations, and views.

##### CSU: Spec Missing Required @CSU-089

> file_path: models/default/proofs/sd_101_spec_missing_required.lua

> language: Lua

> description: Proof view detecting specifications missing required attributes.

> traceability: [CSC-020](@)

##### CSU: Spec Invalid Type @CSU-090

> file_path: models/default/proofs/sd_102_spec_invalid_type.lua

> language: Lua

> description: Proof view detecting specifications whose type_ref does not match any registered specification type.

> traceability: [CSC-020](@)

##### CSU: Object Missing Required @CSU-091

> file_path: models/default/proofs/sd_201_object_missing_required.lua

> language: Lua

> description: Proof view detecting spec objects missing required attributes.

> traceability: [CSC-020](@)

##### CSU: Object Cardinality Over @CSU-092

> file_path: models/default/proofs/sd_202_object_cardinality_over.lua

> language: Lua

> description: Proof view detecting spec object attributes exceeding their declared max_occurs cardinality.

> traceability: [CSC-020](@)

##### CSU: Object Cast Failures @CSU-093

> file_path: models/default/proofs/sd_203_object_cast_failures.lua

> language: Lua

> description: Proof view detecting spec object attributes whose raw values failed to cast to their declared datatype.

> traceability: [CSC-020](@)

##### CSU: Object Invalid Enum @CSU-094

> file_path: models/default/proofs/sd_204_object_invalid_enum.lua

> language: Lua

> description: Proof view detecting spec object ENUM attributes with values not matching any entry in enum_values.

> traceability: [CSC-020](@)

##### CSU: Object Invalid Date @CSU-095

> file_path: models/default/proofs/sd_205_object_invalid_date.lua

> language: Lua

> description: Proof view detecting spec object DATE attributes not matching the YYYY-MM-DD format.

> traceability: [CSC-020](@)

##### CSU: Object Bounds Violation @CSU-096

> file_path: models/default/proofs/sd_206_object_bounds_violation.lua

> language: Lua

> description: Proof view detecting numeric attributes falling outside declared min_value/max_value bounds.

> traceability: [CSC-020](@)

##### CSU: Float Orphan @CSU-097

> file_path: models/default/proofs/sd_301_float_orphan.lua

> language: Lua

> description: Proof view detecting floats with no parent object despite objects existing in the same specification.

> traceability: [CSC-020](@)

##### CSU: Float Duplicate Label @CSU-098

> file_path: models/default/proofs/sd_302_float_duplicate_label.lua

> language: Lua

> description: Proof view detecting floats sharing the same label within a specification.

> traceability: [CSC-020](@)

##### CSU: Float Render Failure @CSU-099

> file_path: models/default/proofs/sd_303_float_render_failure.lua

> language: Lua

> description: Proof view detecting floats requiring external rendering but with NULL resolved_ast.

> traceability: [CSC-020](@)

##### CSU: Float Invalid Type @CSU-100

> file_path: models/default/proofs/sd_304_float_invalid_type.lua

> language: Lua

> description: Proof view detecting floats whose type_ref does not match any registered float type.

> traceability: [CSC-020](@)

##### CSU: Relation Unresolved @CSU-101

> file_path: models/default/proofs/sd_401_relation_unresolved.lua

> language: Lua

> description: Proof view detecting relations with target_text but no resolved target_ref.

> traceability: [CSC-020](@)

##### CSU: Relation Dangling @CSU-102

> file_path: models/default/proofs/sd_402_relation_dangling.lua

> language: Lua

> description: Proof view detecting relations whose target_ref points to a non-existent identifier.

> traceability: [CSC-020](@)

##### CSU: Relation Ambiguous @CSU-103

> file_path: models/default/proofs/sd_407_relation_ambiguous.lua

> language: Lua

> description: Proof view detecting relations flagged as ambiguous where the float reference matched multiple targets.

> traceability: [CSC-020](@)

##### CSU: View Materialization Failure @CSU-104

> file_path: models/default/proofs/sd_501_view_materialization_failure.lua

> language: Lua

> description: Proof view detecting views whose materialization failed, leaving both resolved_ast and resolved_data as NULL.

> traceability: [CSC-020](@)

##### Default Styles Package

#### CSC: Default Styles @CSC-021

> component_type: Package

> path: models/default/styles/default/

> description: Style presets defining page layout, typography, and formatting for DOCX and HTML output.

##### CSU: DOCX Style Preset @CSU-106

> file_path: models/default/styles/default/docx.lua

> language: Lua

> description: Defines the default DOCX style preset with Letter-sized page configuration, paragraph styles, and standard margins for Word document output.

> traceability: [CSC-021](@)

##### CSU: HTML Style Preset @CSU-107

> file_path: models/default/styles/default/html.lua

> language: Lua

> description: Defines the default HTML style preset with typography (Inter/JetBrains Mono fonts), color palette, and layout configuration for web output.

> traceability: [CSC-021](@)

##### Default Float Types Package

#### CSC: Default Float Types @CSC-022

> component_type: Package

> path: models/default/types/floats/

> description: Float type definitions for numbered content blocks including images, tables, code listings, diagrams, charts, and equations.

##### CSU: CHART Float Type @CSU-108

> file_path: models/default/types/floats/chart.lua

> language: Lua

> description: Defines the CHART float type for ECharts JSON configurations rendered to PNG via Deno; shares FIGURE counter group and requires external rendering.

> traceability: [CSC-022](@)

##### CSU: FIGURE Float Type @CSU-109

> file_path: models/default/types/floats/figure.lua

> language: Lua

> description: Defines the FIGURE float type for existing image files (PNG, JPG, etc.); does not require external rendering and resolves image paths relative to the source file.

> traceability: [CSC-022](@)

##### CSU: LISTING Float Type @CSU-110

> file_path: models/default/types/floats/listing.lua

> language: Lua

> description: Defines the LISTING float type for code listings and source code blocks; has its own counter group, supports aliases like src, quadro, and code.

> traceability: [CSC-022](@)

##### CSU: MATH Float Type @CSU-111

> file_path: models/default/types/floats/math.lua

> language: Lua

> description: Defines the MATH float type for block-level AsciiMath expressions converted to MathML/OMML; uses the EQUATION counter group and requires external rendering.

> traceability: [CSC-022](@)

##### CSU: PLANTUML Float Type @CSU-112

> file_path: models/default/types/floats/plantuml.lua

> language: Lua

> description: Defines the PLANTUML float type for PlantUML diagrams rendered to PNG; shares the FIGURE counter group and requires external rendering.

> traceability: [CSC-022](@)

##### CSU: TABLE Float Type @CSU-113

> file_path: models/default/types/floats/table.lua

> language: Lua

> description: Defines the TABLE float type for tables parsed from CSV, TSV, or list-table syntax using Pandoc's built-in readers; has its own counter group.

> traceability: [CSC-022](@)

##### Default Relation Types Package

#### CSC: Default Relation Types @CSC-023

> component_type: Package

> path: models/default/types/relations/

> description: Cross-reference relation type definitions mapping link selectors to target float types.

##### CSU: XREF_CITATION Relation Type @CSU-114

> file_path: models/default/types/relations/xref_citation.lua

> language: Lua

> description: Defines the XREF_CITATION relation type for cross-references to bibliography entries; uses the # link selector with cite/citep prefix aliases.

> traceability: [CSC-023](@)

##### CSU: XREF_FIGURE Relation Type @CSU-115

> file_path: models/default/types/relations/xref_figure.lua

> language: Lua

> description: Defines the XREF_FIGURE relation type for cross-references to FIGURE, PLANTUML, and CHART floats; default relation type for # references.

> traceability: [CSC-023](@)

##### CSU: XREF_LISTING Relation Type @CSU-116

> file_path: models/default/types/relations/xref_listing.lua

> language: Lua

> description: Defines the XREF_LISTING relation type for cross-references to LISTING floats; uses the # link selector.

> traceability: [CSC-023](@)

##### CSU: XREF_MATH Relation Type @CSU-117

> file_path: models/default/types/relations/xref_math.lua

> language: Lua

> description: Defines the XREF_MATH relation type for cross-references to MATH floats; uses the # link selector.

> traceability: [CSC-023](@)

##### CSU: XREF_TABLE Relation Type @CSU-118

> file_path: models/default/types/relations/xref_table.lua

> language: Lua

> description: Defines the XREF_TABLE relation type for cross-references to TABLE floats; uses the # link selector.

> traceability: [CSC-023](@)

##### Default View Types Package

#### CSC: Default View Types @CSC-024

> component_type: Package

> path: models/default/types/views/

> description: View type definitions for inline and block-level data-driven content rendering.

##### CSU: ABBREV View Type @CSU-119

> file_path: models/default/types/views/abbrev.lua

> language: Lua

> description: Defines the ABBREV view type for inline abbreviation/acronym definitions using abbrev: syntax with first-use expansion support.

> traceability: [CSC-024](@)

##### CSU: ABBREV_LIST View Type @CSU-120

> file_path: models/default/types/views/abbrev_list.lua

> language: Lua

> description: Defines the ABBREV_LIST view type for generating a sorted list of all abbreviations defined in the document.

> traceability: [CSC-024](@)

##### CSU: GAUSS View Type @CSU-121

> file_path: models/default/types/views/gauss.lua

> language: Lua

> description: Defines the GAUSS view type for generating Gaussian distribution data from inline gauss: syntax with configurable parameters; returns ECharts dataset format.

> traceability: [CSC-024](@)

##### CSU: LOF View Type @CSU-122

> file_path: models/default/types/views/lof.lua

> language: Lua

> description: Defines the LOF view type for generating lists of floats (figures, tables) from inline lof:/lot: syntax; queries spec_floats by counter_group.

> traceability: [CSC-024](@)

##### CSU: MATH_INLINE View Type @CSU-123

> file_path: models/default/types/views/math_inline.lua

> language: Lua

> description: Defines the MATH_INLINE view type for inline AsciiMath expressions using math:/eq:/formula: syntax; requires external rendering for MathML-to-OMML conversion.

> traceability: [CSC-024](@)

##### CSU: TOC View Type @CSU-124

> file_path: models/default/types/views/toc.lua

> language: Lua

> description: Defines the TOC view type for generating a table of contents from inline toc: syntax with optional depth parameter.

> traceability: [CSC-024](@)

---

### SW Docs Model Components

#### SW Docs Model

#### CSC: SW Docs Model @CSC-025

> component_type: Model

> path: models/sw_docs/

> description: Domain model for software documentation providing traceable object types, domain-specific proof views, specification types, relation types, and views.

##### CSU: HTML5 Postprocessor @CSU-125

> file_path: models/sw_docs/postprocessors/html5.lua

> language: Lua

> description: HTML5 post-processor that generates a single-file documentation web app with embedded CSS, JS, content, and SQLite-WASM full-text search.

> traceability: [CSC-025](@)

##### SW Docs Proof Views Package

#### CSC: SW Docs Proof Views @CSC-026

> component_type: Package

> path: models/sw_docs/proofs/

> description: Domain-specific proof view queries for software documentation traceability and naming convention enforcement.

##### CSU: VC Missing HLR Traceability @CSU-126

> file_path: models/sw_docs/proofs/sd_601_vc_missing_hlr_traceability.lua

> language: Lua

> description: Proof view detecting verification cases with no traceability link to any high-level requirement.

> traceability: [CSC-026](@)

##### CSU: TR Missing VC Traceability @CSU-127

> file_path: models/sw_docs/proofs/sd_602_tr_missing_vc_traceability.lua

> language: Lua

> description: Proof view detecting test results with no traceability link to any verification case.

> traceability: [CSC-026](@)

##### CSU: HLR Missing VC Coverage @CSU-128

> file_path: models/sw_docs/proofs/sd_603_hlr_missing_vc_coverage.lua

> language: Lua

> description: Proof view detecting high-level requirements not covered by any verification case.

> traceability: [CSC-026](@)

##### CSU: FD Missing CSC Traceability @CSU-131

> file_path: models/sw_docs/proofs/sd_606_fd_missing_csc_traceability.lua

> language: Lua

> description: Proof view detecting functional descriptions with no traceability link to any Computer Software Component.

> traceability: [CSC-026](@)

##### CSU: FD Missing CSU Traceability @CSU-132

> file_path: models/sw_docs/proofs/sd_607_fd_missing_csu_traceability.lua

> language: Lua

> description: Proof view detecting functional descriptions with no traceability link to any Computer Software Unit.

> traceability: [CSC-026](@)

##### CSU: CSC Missing FD Allocation @CSU-163

> file_path: models/sw_docs/proofs/csc_missing_fd_allocation.lua

> language: Lua

> description: Proof view detecting Computer Software Components with no functional description (FD) allocated to them.

> traceability: [CSC-026](@)

##### CSU: CSU Missing FD Allocation @CSU-164

> file_path: models/sw_docs/proofs/csu_missing_fd_allocation.lua

> language: Lua

> description: Proof view detecting Computer Software Units with no functional description (FD) allocated to them.

> traceability: [CSC-026](@)

##### SW Docs Object Types Package

#### CSC: SW Docs Object Types @CSC-027

> component_type: Package

> path: models/sw_docs/types/objects/

> description: Domain object type definitions for traceable specification items including requirements, design decisions, verification cases, and MIL-STD-498 architectural elements.

##### CSU: CSC Object Type @CSU-133

> file_path: models/sw_docs/types/objects/csc.lua

> language: Lua

> description: Defines the CSC (Computer Software Component) object type for MIL-STD-498 architectural decomposition, with required component_type and path attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: CSU Object Type @CSU-134

> file_path: models/sw_docs/types/objects/csu.lua

> language: Lua

> description: Defines the CSU (Computer Software Unit) object type for implementation-level source file units, with required file_path and optional language attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: DD Object Type @CSU-135

> file_path: models/sw_docs/types/objects/dd.lua

> language: Lua

> description: Defines the DD (Design Decision) object type for recording architectural decisions, with a required rationale XHTML attribute, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: DIC Object Type @CSU-136

> file_path: models/sw_docs/types/objects/dic.lua

> language: Lua

> description: Defines the DIC (Dictionary Entry) object type for project term definitions, with optional term, acronym, and domain attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: FD Object Type @CSU-137

> file_path: models/sw_docs/types/objects/fd.lua

> language: Lua

> description: Defines the FD (Functional Description) object type for design elements that realize Software Functions, with optional traceability XHTML attribute, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: HLR Object Type @CSU-138

> file_path: models/sw_docs/types/objects/hlr.lua

> language: Lua

> description: Defines the HLR (High-Level Requirement) object type for top-level system requirements, with priority enum (High/Mid/Low), rationale, and belongs_to attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: LLR Object Type @CSU-139

> file_path: models/sw_docs/types/objects/llr.lua

> language: Lua

> description: Defines the LLR (Low-Level Requirement) object type for detailed implementation requirements derived from HLRs, with optional rationale, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: NFR Object Type @CSU-140

> file_path: models/sw_docs/types/objects/nfr.lua

> language: Lua

> description: Defines the NFR (Non-Functional Requirement) object type for quality-attribute requirements, with category enum, priority, and metric attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: SF Object Type @CSU-141

> file_path: models/sw_docs/types/objects/sf.lua

> language: Lua

> description: Defines the SF (Software Function) object type for grouping related HLRs into functional units, with optional description and rationale attributes, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: SYMBOL Object Type @CSU-142

> file_path: models/sw_docs/types/objects/symbol.lua

> language: Lua

> description: Defines the SYMBOL object type for code symbols (functions, variables, registers) extracted from firmware analysis, with kind, source, complexity, and calls attributes.

> traceability: [CSC-027](@)

##### CSU: TR Object Type @CSU-143

> file_path: models/sw_docs/types/objects/tr.lua

> language: Lua

> description: Defines the TR (Test Result) object type for verification-case execution outcomes, with required result enum (Pass/Fail/Blocked/Not Run) and required traceability to a VC, extending TRACEABLE.

> traceability: [CSC-027](@)

##### CSU: TRACEABLE Base Object Type @CSU-144

> file_path: models/sw_docs/types/objects/traceable.lua

> language: Lua

> description: Defines the TRACEABLE abstract base object type that all traceable objects extend; provides the inherited status enum attribute (Draft/Review/Approved/Implemented) and extends SECTION.

> traceability: [CSC-027](@)

##### CSU: VC Object Type @CSU-145

> file_path: models/sw_docs/types/objects/vc.lua

> language: Lua

> description: Defines the VC (Verification Case) object type for test specifications, with required objective and verification_method attributes plus optional preconditions, expected results, and pass criteria, extending TRACEABLE.

> traceability: [CSC-027](@)

##### SW Docs Relation Types Package

#### CSC: SW Docs Relation Types @CSC-028

> component_type: Package

> path: models/sw_docs/types/relations/

> description: Domain relation type definitions for traceability links between software documentation elements.

##### CSU: BELONGS Relation Type @CSU-146

> file_path: models/sw_docs/types/relations/belongs.lua

> language: Lua

> description: Defines the BELONGS relation type representing HLR membership in a Software Function (SF), resolved from the belongs_to source attribute using the @ link selector.

> traceability: [CSC-028](@)

##### CSU: REALIZES Relation Type @CSU-147

> file_path: models/sw_docs/types/relations/realizes.lua

> language: Lua

> description: Defines the REALIZES relation type representing a Functional Description (FD) realizing a Software Function (SF), resolved from the traceability source attribute.

> traceability: [CSC-028](@)

##### CSU: TRACES_TO Relation Type @CSU-148

> file_path: models/sw_docs/types/relations/traces_to.lua

> language: Lua

> description: Defines the TRACES_TO relation type, the default (is_default=true) general-purpose traceability link using the @ link selector with no source/target type constraints.

> traceability: [CSC-028](@)

##### CSU: XREF_DIC Relation Type @CSU-149

> file_path: models/sw_docs/types/relations/xref_dic.lua

> language: Lua

> description: Defines the XREF_DIC relation type for cross-references targeting Dictionary (DIC) entries from any source type, using the @ link selector.

> traceability: [CSC-028](@)

##### SW Docs Specification Types Package

#### CSC: SW Docs Specification Types @CSC-029

> component_type: Package

> path: models/sw_docs/types/specifications/

> description: Specification type definitions for SDN document types (SRS, SDD, SVC, SUM, TRR).

##### CSU: SDD Specification Type @CSU-150

> file_path: models/sw_docs/types/specifications/sdd.lua

> language: Lua

> description: Defines the SDD (Software Design Description) specification type with required version, optional status and date attributes.

> traceability: [CSC-029](@)

##### CSU: SRS Specification Type @CSU-151

> file_path: models/sw_docs/types/specifications/srs.lua

> language: Lua

> description: Defines the SRS (Software Requirements Specification) specification type with required version, optional status and date attributes.

> traceability: [CSC-029](@)

##### CSU: SUM Specification Type @CSU-152

> file_path: models/sw_docs/types/specifications/sum.lua

> language: Lua

> description: Defines the SUM (Software User Manual) specification type for user manuals, with required version, optional status and date attributes.

> traceability: [CSC-029](@)

##### CSU: SVC Specification Type @CSU-153

> file_path: models/sw_docs/types/specifications/svc.lua

> language: Lua

> description: Defines the SVC (Software Verification Cases) specification type with required version, optional status and date attributes.

> traceability: [CSC-029](@)

##### CSU: TRR Specification Type @CSU-154

> file_path: models/sw_docs/types/specifications/trr.lua

> language: Lua

> description: Defines the TRR (Test Results Report) specification type for aggregating test-execution results, with required version plus optional test_run_id and environment attributes.

> traceability: [CSC-029](@)

##### SW Docs View Types Package

#### CSC: SW Docs View Types @CSC-030

> component_type: Package

> path: models/sw_docs/types/views/

> description: Domain view type definitions for traceability matrices, test results, and coverage summaries.

##### CSU: Coverage Summary View @CSU-155

> file_path: models/sw_docs/types/views/coverage_summary.lua

> language: Lua

> description: Defines the COVERAGE_SUMMARY view generating a table of VC counts and pass rates grouped by Software Function (SF).

> traceability: [CSC-030](@)

##### CSU: Requirements Summary View @CSU-156

> file_path: models/sw_docs/types/views/requirements_summary.lua

> language: Lua

> description: Defines the REQUIREMENTS_SUMMARY view generating a table of HLR counts grouped by Software Function (SF) via the BELONGS relation.

> traceability: [CSC-030](@)

##### CSU: Test Execution Matrix View @CSU-157

> file_path: models/sw_docs/types/views/test_execution_matrix.lua

> language: Lua

> description: Defines the TEST_EXECUTION_MATRIX view generating a deterministic VC-to-HLR-to-procedure/oracle matrix from the SpecIR.

> traceability: [CSC-030](@)

##### CSU: Test Results Matrix View @CSU-158

> file_path: models/sw_docs/types/views/test_results_matrix.lua

> language: Lua

> description: Defines the TEST_RESULTS_MATRIX view generating a table of VC-to-TR traceability with pass/fail result status.

> traceability: [CSC-030](@)

##### CSU: Traceability Matrix View @CSU-159

> file_path: models/sw_docs/types/views/traceability_matrix.lua

> language: Lua

> description: Defines the TRACEABILITY_MATRIX view generating a table showing the full HLR-to-VC-to-TR traceability chain with test results.

> traceability: [CSC-030](@)

