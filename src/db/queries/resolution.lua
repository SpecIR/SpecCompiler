---Resolution queries for SpecCompiler.
-- Queries for resolving relations, floats, types, and cross-references.
-- Uses INTEGER id columns for JOINs, unified label for # selector resolution.

local M = {}

-- ============================================================================
-- RELATION TYPE RESOLUTION
-- ============================================================================

-- Get relation inference rules from spec_relation_types
-- Rules define when relations are auto-inferred from attributes or types
-- Returns all 4 quadruple components: (selector, source, attr, target)
M.inference_rules = [[
    SELECT
        identifier as rel_type,
        link_selector as selector,
        source_type_ref as source,
        target_type_ref as target,
        source_attribute as attr
    FROM spec_relation_types
    WHERE identifier NOT IN (
        SELECT DISTINCT extends FROM spec_relation_types WHERE extends IS NOT NULL
    )
]]

-- ============================================================================
-- FLOAT TYPE RESOLUTION
-- ============================================================================

-- Get float type definition by identifier (aliases included for prefix extraction)
M.select_float_type_by_id = [[
    SELECT identifier, aliases FROM spec_float_types
    WHERE identifier = :type_ref
]]

-- Resolve a float type alias to its canonical identifier
-- Matches by exact identifier or comma-wrapped alias pattern
M.resolve_float_type_alias = [[
    SELECT identifier FROM spec_float_types
    WHERE identifier = :alias
       OR (aliases IS NOT NULL AND aliases LIKE :like_pattern)
]]

-- Check if a float type exists by identifier
M.float_type_exists = [[
    SELECT 1 FROM spec_float_types WHERE identifier = :id
]]

-- Resolve float type from prefix/alias (e.g., fig -> FIGURE)
-- Matches identifier or comma-wrapped aliases
M.float_type_from_prefix = [[
    SELECT identifier FROM spec_float_types
    WHERE LOWER(identifier) = :prefix
       OR (aliases IS NOT NULL AND aliases LIKE :like_pattern)
]]

-- Infer relation type from target float type
-- Finds relation types that target the given float type
M.relation_type_from_target_float = [[
    SELECT identifier FROM spec_relation_types
    WHERE link_selector = '#'
      AND (
          target_type_ref = :target_type
          OR target_type_ref LIKE :target_pattern_start
          OR target_type_ref LIKE :target_pattern_end
          OR target_type_ref LIKE :target_pattern_mid
      )
]]

-- ============================================================================
-- FLOAT RESOLUTION (for cross-references)
-- ============================================================================

-- Resolve float by label within a parent scope (scoped resolution)
-- First priority: float in same parent object
M.float_by_label_scoped = [[
    SELECT id, label, anchor, parent_object_id
    FROM spec_floats
    WHERE label = :label
      AND parent_object_id = :parent_id
    LIMIT 1
]]

-- Resolve float by label globally (fallback when no scope match)
M.float_by_label_global = [[
    SELECT id, label, anchor, parent_object_id
    FROM spec_floats
    WHERE label = :label
    LIMIT 1
]]

-- Resolve float by anchor directly
M.float_by_anchor = [[
    SELECT id, label, parent_object_id
    FROM spec_floats
    WHERE anchor = :anchor
    LIMIT 1
]]

-- Get float's anchor for a given label within parent scope
M.float_anchor_scoped = [[
    SELECT anchor
    FROM spec_floats
    WHERE label = :label
      AND parent_object_id = :parent_id
    LIMIT 1
]]

-- ============================================================================
-- OBJECT RESOLUTION (for @PID references)
-- ============================================================================

-- Resolve object by PID
M.object_by_pid = [[
    SELECT id, pid, title_text, label, from_file
    FROM spec_objects
    WHERE pid = :pid
    LIMIT 1
]]

-- Resolve object by integer id
M.object_by_id = [[
    SELECT id, pid, title_text, label, from_file
    FROM spec_objects
    WHERE id = :id
    LIMIT 1
]]

-- Resolve object by label (for # selector)
M.object_by_label = [[
    SELECT id, pid, title_text, label, type_ref, from_file
    FROM spec_objects
    WHERE specification_ref = :spec_id AND label = :label
    LIMIT 1
]]

-- ============================================================================
-- UNIFIED LABEL RESOLUTION (# selector — objects AND floats)
-- ============================================================================

-- Search both objects and floats by label (unified namespace)
M.resolve_by_label = [[
    SELECT id, label, type_ref, 'object' as kind FROM spec_objects
    WHERE specification_ref = :spec_id AND label = :label
    UNION ALL
    SELECT id, label, type_ref, 'float' as kind FROM spec_floats
    WHERE specification_ref = :spec_id AND label = :label
]]

-- ============================================================================
-- RELATION RESOLVER: PID-based target lookup (@ selector)
-- ============================================================================

-- Find target object by PID within same specification
M.object_by_pid_in_spec = [[
    SELECT id, type_ref FROM spec_objects
    WHERE specification_ref = :spec AND pid = :pid
]]

-- Find target object by PID across all specifications (cross-doc fallback)
M.object_by_pid_cross_doc = [[
    SELECT id, type_ref FROM spec_objects
    WHERE pid = :pid
]]

-- Find scope object by PID within same specification (for explicit scope resolution)
M.scope_object_by_pid_in_spec = [[
    SELECT id FROM spec_objects
    WHERE specification_ref = :spec_id AND pid = :pid
]]

-- Find scope object by PID across all specifications (for explicit scope resolution)
M.scope_object_by_pid_cross_doc = [[
    SELECT id FROM spec_objects WHERE pid = :pid
]]

-- ============================================================================
-- RELATION RESOLVER: Label-based target lookup (# selector)
-- ============================================================================

-- Find float by label within an explicit scope object (returns typed kind column)
M.float_by_label_in_scope_typed = [[
    SELECT id, type_ref, 'float' as kind FROM spec_floats
    WHERE label = :label AND parent_object_id = :scope_id
]]

-- Find objects and floats by label within same specification (unified namespace)
M.unified_by_label_in_spec = [[
    SELECT id, type_ref, 'object' as kind FROM spec_objects
    WHERE specification_ref = :spec AND label = :label
    UNION ALL
    SELECT id, type_ref, 'float' as kind FROM spec_floats
    WHERE specification_ref = :spec AND label = :label
]]

-- Find objects and floats by label across all specifications (global fallback)
M.unified_by_label_global = [[
    SELECT id, type_ref, 'object' as kind FROM spec_objects
    WHERE label = :label
    UNION ALL
    SELECT id, type_ref, 'float' as kind FROM spec_floats
    WHERE label = :label
]]

-- ============================================================================
-- STALE REFERENCE CLEANUP (incremental builds)
-- ============================================================================

-- Null out target_object_id (and type_ref) for relations pointing to deleted objects.
-- Needed when cached documents have cross-doc references to reprocessed docs
-- whose objects were re-created with new auto-increment IDs.
-- Also nulls type_ref so stale cached relations get re-analyzed.
M.null_dangling_object_targets = [[
    UPDATE spec_relations SET target_object_id = NULL, type_ref = NULL
    WHERE target_object_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM spec_objects WHERE id = spec_relations.target_object_id)
]]

-- Null out target_float_id (and type_ref) for relations pointing to deleted floats.
M.null_dangling_float_targets = [[
    UPDATE spec_relations SET target_float_id = NULL, type_ref = NULL
    WHERE target_float_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM spec_floats WHERE id = spec_relations.target_float_id)
]]

-- Find specs with unresolved relations (for re-analysis after stale cleanup).
-- No selector filter — any relation needing analysis is included.
M.specs_with_unresolved_relations = [[
    SELECT DISTINCT specification_ref
    FROM spec_relations
    WHERE target_object_id IS NULL
      AND target_float_id IS NULL
      AND type_ref IS NULL
      AND target_text IS NOT NULL
]]

-- ============================================================================
-- RELATION RESOLUTION
-- ============================================================================

-- Get unresolved relations eligible for type-driven analysis.
-- No selector filter — any untyped relation with target_text is eligible.
-- The relation_analyzer determines resolution strategy from candidate types.
M.unresolved_relations_for_analysis = [[
    SELECT r.id, r.source_object_id, r.target_text, r.from_file,
           r.link_line, r.link_selector, r.source_attribute,
           r.specification_ref, so.type_ref AS source_type
    FROM spec_relations r
    LEFT JOIN spec_objects so ON so.id = r.source_object_id
    WHERE r.specification_ref = :spec_id
      AND r.target_object_id IS NULL
      AND r.target_float_id IS NULL
      AND r.type_ref IS NULL
      AND r.target_text IS NOT NULL
]]

-- Get unresolved relations (both target columns NULL)
M.unresolved_relations = [[
    SELECT
        r.id,
        r.source_object_id,
        r.target_text,
        r.type_ref,
        r.from_file,
        r.link_selector,
        r.source_attribute
    FROM spec_relations r
    WHERE r.target_object_id IS NULL
      AND r.target_float_id IS NULL
      AND r.target_text IS NOT NULL
]]

-- Update relation with resolved target (object)
M.resolve_relation_to_object = [[
    UPDATE spec_relations
    SET target_object_id = :target_object_id, is_ambiguous = :is_ambiguous
    WHERE id = :id
]]

-- Update relation with resolved target (float)
M.resolve_relation_to_float = [[
    UPDATE spec_relations
    SET target_float_id = :target_float_id, is_ambiguous = :is_ambiguous
    WHERE id = :id
]]

-- ============================================================================
-- ENUM RESOLUTION
-- ============================================================================

-- Look up enum value by datatype and key (for attribute casting)
M.enum_value_by_type_and_key = [[
    SELECT identifier FROM enum_values
    WHERE datatype_ref = :type AND key = :key
]]

-- ============================================================================
-- TYPE DEFAULTS
-- ============================================================================

-- Get default object type from spec_object_types
-- Used when objects don't have explicit type declaration
M.default_object_type = [[
    SELECT identifier FROM spec_object_types
    WHERE is_default = 1
    LIMIT 1
]]

-- ============================================================================
-- ATTRIBUTE RESOLUTION
-- ============================================================================

-- Get attribute definition with datatype for validation
-- Joins to datatype_definitions for type info
M.attribute_definition = [[
    SELECT ad.identifier, ad.datatype_ref, dd.type as datatype,
           ad.min_value, ad.max_value
    FROM spec_attribute_types ad
    JOIN datatype_definitions dd ON ad.datatype_ref = dd.identifier
    WHERE ad.owner_type_ref = :owner_type AND ad.long_name = :name
]]

-- Get spec_object by file_seq (header sequence number)
-- Used to find owner object for attributes
M.object_by_file_seq = [[
    SELECT id, type_ref, title_text, label, start_line, file_seq
    FROM spec_objects
    WHERE specification_ref = :spec_id
      AND file_seq = :file_seq
    LIMIT 1
]]

-- ============================================================================
-- SPECIFICATION RESOLUTION
-- ============================================================================

-- Get specification by identifier
M.specification_by_id = [[
    SELECT identifier FROM specifications WHERE identifier = :spec_id
]]

-- ============================================================================
-- PARENT OBJECT RESOLUTION
-- ============================================================================

-- Find the parent spec_object that contains a given line (deepest container).
-- Returns the most specific (deepest nested) object whose line range includes the link.
M.find_parent_object_by_line = [[
    SELECT id FROM spec_objects
    WHERE specification_ref = :spec_id
      AND from_file = :from_file
      AND start_line <= :line
      AND (end_line IS NULL OR end_line >= :line)
    ORDER BY level DESC, start_line DESC
    LIMIT 1
]]

-- ============================================================================
-- ATTRIBUTE LINK EXTRACTION
-- ============================================================================

-- Get attribute values with AST for link extraction within a specification.
-- Joins to spec_objects to get source file/line info for each attribute.
M.select_attributes_with_ast_by_spec = [[
    SELECT av.owner_object_id, av.ast, av.specification_ref, av.name as attr_name,
           so.from_file as owner_file, so.start_line as owner_line
    FROM spec_attribute_values av
    JOIN spec_objects so ON av.owner_object_id = so.id
    WHERE av.specification_ref = :spec_id
      AND av.ast IS NOT NULL
      AND av.owner_object_id IS NOT NULL
]]

-- ============================================================================
-- RELATION TYPE INFERENCE (used by relation_analyzer)
-- ============================================================================

-- Update relation with inferred type
M.update_relation_type = [[
    UPDATE spec_relations SET type_ref = :type_ref WHERE id = :id
]]

-- Mark relation as ambiguous (tie between inference rules)
M.mark_relation_ambiguous = [[
    UPDATE spec_relations SET is_ambiguous = 1 WHERE id = :id
]]

-- ============================================================================
-- RELATION LINK REWRITING
-- ============================================================================

-- Get all resolved relations with target details for link rewriting.
-- Joins float types for caption_format and objects for PID.
M.select_resolved_relations_with_targets = [[
    SELECT r.source_object_id, r.target_text, r.link_selector,
           r.type_ref AS relation_type_ref,
           tf.anchor AS float_anchor, tf.label AS float_label,
           tf.number AS float_number, tf.specification_ref AS float_spec,
           tft.caption_format,
           to2.pid AS object_pid, to2.specification_ref AS object_spec,
           to2.title_text AS object_title_text, to2.type_ref AS object_type_ref
    FROM spec_relations r
    LEFT JOIN spec_floats tf ON r.target_float_id = tf.id
    LEFT JOIN spec_float_types tft ON tf.type_ref = tft.identifier
    LEFT JOIN spec_objects to2 ON r.target_object_id = to2.id
    WHERE r.specification_ref = :spec_id
      AND (r.target_float_id IS NOT NULL OR r.target_object_id IS NOT NULL)
]]

-- ============================================================================
-- INSERT OPERATIONS
-- ============================================================================

-- Insert a new relation (integer FK columns)
M.insert_relation = [[
    INSERT INTO spec_relations (
        content_sha, specification_ref, source_object_id,
        target_text, target_object_id, target_float_id,
        type_ref, from_file, link_line, source_attribute, link_selector
    ) VALUES (
        :content_sha, :specification_ref, :source_object_id,
        :target_text, :target_object_id, :target_float_id,
        :type_ref, :from_file, :link_line, :source_attribute, :link_selector
    )
]]

return M
