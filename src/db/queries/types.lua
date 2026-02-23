---Type system queries for SpecCompiler.
-- INSERT/SELECT operations for spec_object_types, spec_float_types,
-- spec_relation_types, spec_view_types, spec_specification_types,
-- datatype_definitions, spec_attribute_types, enum_values, implicit_type_aliases.

local M = {}

-- ============================================================================
-- Float Types
-- ============================================================================

M.insert_float_type = [[
    INSERT OR REPLACE INTO spec_float_types (
        identifier, long_name, description, caption_format, counter_group, aliases, needs_external_render
    ) VALUES (
        :identifier, :long_name, :description, :caption_format, :counter_group, :aliases, :needs_external_render
    )
]]

-- ============================================================================
-- Relation Types
-- ============================================================================

M.insert_relation_type = [[
    INSERT OR REPLACE INTO spec_relation_types (
        identifier, long_name, description, extends, link_selector,
        source_attribute, source_type_ref, target_type_ref
    ) VALUES (
        :identifier, :long_name, :description, :extends, :link_selector,
        :source_attribute, :source_type_ref, :target_type_ref
    )
]]

-- ============================================================================
-- Object Types
-- ============================================================================

M.insert_object_type = [[
    INSERT OR REPLACE INTO spec_object_types (
        identifier, long_name, description, extends, is_composite, is_required, is_default, pid_prefix, pid_format, aliases
    ) VALUES (
        :identifier, :long_name, :description, :extends, :is_composite, :is_required, :is_default, :pid_prefix, :pid_format, :aliases
    )
]]

M.insert_implicit_alias = [[
    INSERT OR REPLACE INTO implicit_type_aliases (alias, object_type_id)
    VALUES (:alias, :type_id)
]]

-- ============================================================================
-- View Types
-- ============================================================================

M.insert_view_type = [[
    INSERT OR REPLACE INTO spec_view_types (
        identifier, long_name, description, aliases,
        inline_prefix, materializer_type, counter_group, view_subtype_ref,
        needs_external_render
    ) VALUES (
        :identifier, :long_name, :description, :aliases,
        :inline_prefix, :materializer_type, :counter_group, :view_subtype_ref,
        :needs_external_render
    )
]]

-- ============================================================================
-- Specification Types
-- ============================================================================

M.insert_specification_type = [[
    INSERT OR REPLACE INTO spec_specification_types (
        identifier, long_name, description, extends, is_default
    ) VALUES (
        :identifier, :long_name, :description, :extends, :is_default
    )
]]

M.insert_implicit_spec_alias = [[
    INSERT OR REPLACE INTO implicit_spec_type_aliases (alias, spec_type_id)
    VALUES (:alias, :type_id)
]]

-- ============================================================================
-- Datatype Definitions
-- ============================================================================

M.insert_datatype = [[
    INSERT OR REPLACE INTO datatype_definitions (identifier, long_name, type)
    VALUES (:id, :name, :type)
]]

-- ============================================================================
-- Attribute Definitions
-- ============================================================================

M.insert_attribute_definition = [[
    INSERT OR REPLACE INTO spec_attribute_types (
        identifier, owner_type_ref, long_name, datatype_ref,
        min_occurs, max_occurs, min_value, max_value
    ) VALUES (
        :id, :owner, :long_name, :datatype, :min, :max, :min_value, :max_value
    )
]]

-- ============================================================================
-- Enum Values
-- ============================================================================

M.insert_enum_value = [[
    INSERT OR REPLACE INTO enum_values (
        identifier, datatype_ref, key, sequence
    ) VALUES (
        :id, :datatype, :key, :seq
    )
]]

-- ============================================================================
-- Type Existence & Default Lookups
-- ============================================================================

-- Get default object type from spec_object_types
M.default_object_type = [[
    SELECT identifier FROM spec_object_types
    WHERE is_default = 1
    LIMIT 1
]]

-- Get default specification type from spec_specification_types
M.default_spec_type = [[
    SELECT identifier FROM spec_specification_types
    WHERE is_default = 1
    LIMIT 1
]]

-- Check if an object type exists
M.object_type_exists = [[
    SELECT 1 FROM spec_object_types WHERE identifier = :type_ref
]]

-- Check if a specification type exists
M.spec_type_exists = [[
    SELECT 1 FROM spec_specification_types WHERE identifier = :type_ref
]]

-- Resolve implicit object type alias from title
M.implicit_object_type_alias = [[
    SELECT object_type_id FROM implicit_type_aliases
    WHERE alias = :alias COLLATE NOCASE
    LIMIT 1
]]

-- Resolve implicit specification type alias from title
M.implicit_spec_type_alias = [[
    SELECT spec_type_id FROM implicit_spec_type_aliases
    WHERE alias = :alias COLLATE NOCASE
    LIMIT 1
]]

return M
