---Type system schema tables for SpecCompiler.
-- Defines spec_object_types, spec_float_types, spec_relation_types, spec_view_types,
-- datatype_definitions, spec_attribute_types, enum_values, implicit_type_aliases,
-- and spec_specification_types.

local M = {}

M.SQL = [[
--------------------------------------------------------------------------------
-- TYPE SYSTEM TABLES
--
-- These tables define the metamodel: what types of objects, floats, relations,
-- and views can exist in a specification. Content tables reference these types.
-- Loaded from model configuration at project init time.
--
-- Type tables are dropped and recreated each run because:
--   1. They are fully repopulated from model definitions every run
--   2. Schema changes (added/removed columns) must take effect immediately
--   3. No user data is stored here — only model-defined metamodel entries
-- Build/cache tables (build_graph, source_files, output_cache) are NOT dropped.
--------------------------------------------------------------------------------

DROP TABLE IF EXISTS implicit_spec_type_aliases;
DROP TABLE IF EXISTS implicit_type_aliases;
DROP TABLE IF EXISTS enum_values;
DROP TABLE IF EXISTS spec_attribute_types;
DROP TABLE IF EXISTS spec_view_types;
DROP TABLE IF EXISTS spec_relation_types;
DROP TABLE IF EXISTS spec_float_types;
DROP TABLE IF EXISTS spec_specification_types;
DROP TABLE IF EXISTS datatype_definitions;
DROP TABLE IF EXISTS spec_object_types;

--------------------------------------------------------------------------------
-- 1. OBJECT TYPE DEFINITIONS
-- Defines types of spec objects (HLR, FD, VC, TP, SECTION, etc.)
-- Each object in spec_objects references one of these types.
-- Supports inheritance via 'extends' for shared behavior.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_object_types (
  -- Unique type code (e.g., HLR, FD, VC, TP, SECTION)
  -- Referenced by spec_objects.type_ref
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "High-Level Requirement", "Functional Description")
  long_name TEXT NOT NULL UNIQUE,

  -- Documentation explaining this type's purpose
  description TEXT,

  -- Parent type for inheritance chain
  -- Values: PRE_TEXTUAL, TEXTUAL, POST_TEXTUAL, or another spec_object_type
  -- Enables shared rendering/validation behavior
  extends TEXT,

  -- Boolean (0/1): Is this a container type?
  -- 1 = SECTION type that groups child objects
  -- 0 = Leaf type (actual requirement/test/etc.)
  is_composite INTEGER DEFAULT 0,

  -- Boolean (0/1): Must every spec have at least one of this type?
  -- Used for standard compliance (e.g., ABNT requirements)
  is_required INTEGER DEFAULT 0,

  -- Boolean (0/1): Use this type when header has no explicit type
  -- Only one type should have is_default=1
  is_default INTEGER DEFAULT 0,

  -- Default PID prefix for auto-generation (e.g., "HLR", "VC")
  -- When objects of this type have no @PID and no sibling pattern,
  -- use this prefix to generate PIDs like "HLR-001", "HLR-002"
  pid_prefix TEXT,

  -- Printf format for auto-generated PIDs (e.g., "%s-%03d", "%s-%d")
  -- %s = prefix, %d = sequence number
  -- Default is 3-digit zero-padded: "HLR-001", "HLR-002"
  pid_format TEXT DEFAULT '%s-%03d',

  -- Comma-wrapped aliases for syntax recognition (e.g., ",hlr,req,")
  -- Used to resolve shorthand syntax in link content
  -- Format: ",alias1,alias2," for LIKE queries
  aliases TEXT
);

--------------------------------------------------------------------------------
-- 2. FLOAT TYPE DEFINITIONS
-- Defines types of floats (FIGURE, TABLE, CHART, PLANTUML, MATH, etc.)
-- Floats are numbered elements that can be referenced and captioned.
-- Each float in spec_floats references one of these types.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_float_types (
  -- Unique type code (e.g., FIGURE, TABLE, CHART, PLANTUML)
  -- Referenced by spec_floats.type_ref
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "Figure", "Table", "PlantUML Diagram")
  long_name TEXT NOT NULL UNIQUE,

  -- Documentation explaining this float type's purpose
  description TEXT,

  -- Printf-style format for captions (e.g., "Figure %d", "Table %d")
  -- %d is replaced with the auto-generated number
  caption_format TEXT,

  -- Shared numbering group. Types with same counter_group share a counter.
  -- E.g., FIGURE, CHART, PLANTUML all use counter_group='FIGURE'
  -- so they're numbered Figure 1, Figure 2, Figure 3 regardless of type
  counter_group TEXT,

  -- Comma-wrapped aliases for syntax recognition (e.g., ",fig,puml,plantuml,")
  -- Used to resolve shorthand syntax in code blocks
  -- Format: ",alias1,alias2,alias3," (leading/trailing commas for LIKE queries)
  aliases TEXT,

  -- Boolean (0/1): Does this type need external rendering?
  -- 1 = Requires external tool (e.g., PlantUML server, ECharts)
  -- 0 = Can be rendered directly by Pandoc
  needs_external_render INTEGER DEFAULT 0
);

--------------------------------------------------------------------------------
-- 3. RELATION TYPE DEFINITIONS
-- Defines types of relations between objects (traces_to, verifies, satisfies)
-- Relations enable traceability matrices and coverage analysis.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_relation_types (
  -- Unique relation type code (e.g., TRACES_TO, VERIFIES, SATISFIES, CITES)
  -- Referenced by spec_relations.type_ref
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "Traces To", "Verifies", "Satisfies")
  long_name TEXT NOT NULL UNIQUE,

  -- Documentation explaining this relation's semantics
  description TEXT,

  -- Parent relation type for inheritance chain
  -- Enables shared link_selector and attribute propagation
  extends TEXT,

  -- Constrain source: only objects of this type can be sources
  -- NULL = any object type can be a source
  source_type_ref TEXT,

  -- Constrain target: only objects of this type can be targets
  -- NULL = any object type can be a target
  target_type_ref TEXT,

  -- Link syntax selector (CSV-capable)
  -- "@" = references spec_objects, "#" = references spec_floats
  -- Extended selectors like "@cite,@citep" are supported
  link_selector TEXT,

  -- Attribute name for inference. When set, relation is inferred from attribute.
  -- E.g., source_attribute='allocated_to' creates relation when object has that attr
  source_attribute TEXT,

  FOREIGN KEY (source_type_ref) REFERENCES spec_object_types(identifier),
  FOREIGN KEY (target_type_ref) REFERENCES spec_object_types(identifier)
);

--------------------------------------------------------------------------------
-- 4. VIEW TYPE DEFINITIONS
-- Defines types of views (TOC, LOF, LOT, ABBREV, SYMBOL, MATH_INLINE, etc.)
-- Views are generated content blocks (tables of contents, lists of figures).
-- Each view in spec_views references one of these types.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_view_types (
  -- Unique view type code (e.g., TOC, LOF, LOT, ABBREV, SYMBOL, MATH_INLINE)
  -- Referenced by spec_views.view_type_ref
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "Table of Contents", "List of Figures")
  long_name TEXT NOT NULL UNIQUE,

  -- Documentation explaining this view type's purpose
  description TEXT,

  -- Float counter group to list. Used for LOF/LOT.
  -- E.g., 'FIGURE' for List of Figures, 'TABLE' for List of Tables
  counter_group TEXT,

  -- Comma-wrapped aliases for syntax recognition (e.g., ",sigla,acronym,")
  -- Used to resolve shorthand syntax in code blocks
  aliases TEXT,

  -- Prefix for inline code syntax (e.g., "abbrev", "toc", "math")
  -- Matches syntax like `abbrev:NASA` or `toc:`
  inline_prefix TEXT,

  -- Materialization strategy. Determines how view content is generated.
  -- Values: 'toc', 'lof', 'abbrev_list', 'custom'
  materializer_type TEXT,

  -- For subtyped views (e.g., ABBREV has subtypes SIGLA, ABBREVIATION)
  -- Points to a parent view type
  view_subtype_ref TEXT,

  -- Boolean (0/1): Does this view type need external rendering?
  -- 1 = Requires external tool
  -- 0 = Can be rendered by built-in materializers
  needs_external_render INTEGER DEFAULT 0
);

--------------------------------------------------------------------------------
-- 5. DATATYPE DEFINITIONS
-- Defines primitive data types for attributes (STRING, INTEGER, ENUM, etc.)
-- Part of the EAV (Entity-Attribute-Value) model.
-- Referenced by spec_attribute_types.datatype_ref
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS datatype_definitions (
  -- Unique datatype identifier (e.g., STRING, INTEGER, STATUS_ENUM)
  -- Custom ENUM types are defined here with their values in enum_values
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "Text String", "Integer Number", "Status")
  long_name TEXT NOT NULL UNIQUE,

  -- Primitive type category. Determines which column in spec_attribute_values is used.
  -- STRING  -> spec_attribute_values.string_value
  -- INTEGER -> spec_attribute_values.int_value
  -- REAL    -> spec_attribute_values.real_value
  -- BOOLEAN -> spec_attribute_values.bool_value
  -- DATE    -> spec_attribute_values.date_value (format: YYYY-MM-DD)
  -- ENUM    -> spec_attribute_values.enum_ref (FK to enum_values)
  type TEXT NOT NULL CHECK (type IN ('STRING', 'INTEGER', 'BOOLEAN', 'DATE', 'REAL', 'ENUM', 'XHTML'))
);

--------------------------------------------------------------------------------
-- 6. ATTRIBUTE DEFINITIONS
-- Defines which attributes each object type can have (EAV schema).
-- Includes cardinality and bounds constraints.
-- Validated by proof views (missing_required, cardinality_over, bounds).
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_attribute_types (
  -- Unique attribute definition ID
  identifier TEXT PRIMARY KEY,

  -- Which object type owns this attribute
  -- FK to spec_object_types.identifier
  -- E.g., 'HLR' owns 'status', 'priority', 'rationale'
  owner_type_ref TEXT NOT NULL,

  -- Attribute name as it appears in markdown (e.g., "status", "priority")
  -- Case-sensitive. Used in queries and proof views.
  long_name TEXT NOT NULL,

  -- Data type for this attribute
  -- FK to datatype_definitions.identifier
  datatype_ref TEXT NOT NULL,

  -- Minimum occurrences. 0 = optional, 1+ = required.
  -- Validated by proof view_object_missing_required
  min_occurs INTEGER DEFAULT 0,

  -- Maximum occurrences. 1 = single value, >1 = multi-value attribute.
  -- Validated by proof view_object_cardinality_over
  max_occurs INTEGER DEFAULT 1,

  -- For INTEGER/REAL: minimum allowed value (inclusive)
  -- Validated by proof view_object_bounds_violation
  min_value REAL,

  -- For INTEGER/REAL: maximum allowed value (inclusive)
  -- Validated by proof view_object_bounds_violation
  max_value REAL,

  FOREIGN KEY (datatype_ref) REFERENCES datatype_definitions(identifier),
  -- Each object type can only define an attribute name once
  UNIQUE (owner_type_ref, long_name)
);

--------------------------------------------------------------------------------
-- 7. ENUM VALUES
-- Defines allowed values for ENUM-type datatypes.
-- Each ENUM datatype has multiple entries here.
-- Referenced by spec_attribute_values.enum_ref
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS enum_values (
  -- Unique enum value ID (e.g., 'STATUS_DRAFT', 'STATUS_APPROVED')
  identifier TEXT PRIMARY KEY,

  -- Which ENUM datatype this value belongs to
  -- FK to datatype_definitions.identifier (where type='ENUM')
  datatype_ref TEXT NOT NULL,

  -- The enum key as it appears in markdown (e.g., "draft", "approved")
  key TEXT NOT NULL,

  -- Display order. Lower numbers appear first in dropdowns/lists.
  sequence INTEGER DEFAULT 0,

  FOREIGN KEY (datatype_ref) REFERENCES datatype_definitions(identifier)
);

--------------------------------------------------------------------------------
-- 7b. IMPLICIT TYPE ALIASES
-- Maps header titles to object types for implicit type inference.
-- E.g., "## Introduction" -> SECTION, "## Requirements" -> HLR
-- Case-insensitive matching via COLLATE NOCASE.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS implicit_type_aliases (
  -- Title text that triggers this type (case-insensitive)
  -- E.g., "introduction", "requirements", "test cases"
  alias TEXT PRIMARY KEY COLLATE NOCASE,

  -- Object type to assign when this title is found
  -- FK to spec_object_types.identifier
  object_type_id TEXT NOT NULL,

  FOREIGN KEY (object_type_id) REFERENCES spec_object_types(identifier)
);

--------------------------------------------------------------------------------
-- 7b2. IMPLICIT SPECIFICATION TYPE ALIASES
-- Maps document titles (H1) to specification types.
-- E.g., "# Trabalho Acadêmico" -> TRABALHO_ACADEMICO
-- Case-insensitive matching via COLLATE NOCASE.
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS implicit_spec_type_aliases (
  -- Title text that triggers this type (case-insensitive)
  -- E.g., "trabalho acadêmico", "monografia", "tcc"
  alias TEXT PRIMARY KEY COLLATE NOCASE,

  -- Specification type to assign when this title is found
  -- FK to spec_specification_types.identifier
  spec_type_id TEXT NOT NULL,

  FOREIGN KEY (spec_type_id) REFERENCES spec_specification_types(identifier)
);

--------------------------------------------------------------------------------
-- 7c. SPECIFICATION TYPE DEFINITIONS
-- Defines types of specification documents (SRS, SDD, SVC, MANUAL, etc.)
-- Each specification in specifications table references one of these.
-- Controls document-level rendering (title style, numbering).
--------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS spec_specification_types (
  -- Unique specification type code (e.g., SRS, SDD, SVC, MANUAL)
  -- Referenced by specifications.type_ref
  identifier TEXT PRIMARY KEY,

  -- Human-readable name (e.g., "Software Requirements Specification")
  long_name TEXT NOT NULL UNIQUE,

  -- Documentation explaining this specification type's purpose
  description TEXT,

  -- Parent type for inheritance (e.g., all types extend 'SPEC')
  extends TEXT,

  -- Boolean (0/1): Is this the default specification type?
  -- Used when H1 header has no explicit TYPE: prefix
  is_default INTEGER DEFAULT 0
);

--------------------------------------------------------------------------------
-- INDEXES FOR PROOF VIEW PERFORMANCE
-- These indexes accelerate the VERIFY phase proof views which check data
-- integrity via complex JOINs on type reference columns.
--------------------------------------------------------------------------------

-- spec_attribute_types index for bounds and cardinality proof views
CREATE INDEX IF NOT EXISTS idx_attr_def_owner_type ON spec_attribute_types(owner_type_ref);

-- enum_values index for invalid enum proof view
CREATE INDEX IF NOT EXISTS idx_enum_values_datatype ON enum_values(datatype_ref);
]]

return M
