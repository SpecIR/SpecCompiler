---PID generation queries for SpecCompiler.
-- Queries for auto-generating and managing PIDs for specifications and objects.

local M = {}

-- ============================================================================
-- Specification PIDs
-- ============================================================================

-- Get specifications without a PID (need auto-generation)
M.specs_without_pid = [[
    SELECT identifier, type_ref FROM specifications
    WHERE pid IS NULL OR pid = ''
]]

-- Check if a specification PID already exists (collision detection)
M.spec_pid_exists = [[
    SELECT 1 FROM specifications WHERE pid = :pid
]]

-- Set auto-generated PID on a specification
M.update_spec_pid = [[
    UPDATE specifications SET pid = :pid WHERE identifier = :id
]]

-- ============================================================================
-- Object PIDs: Hierarchical (composite types)
-- ============================================================================

-- Get spec PID for qualifying hierarchical PIDs
M.spec_pid_by_id = [[
    SELECT pid FROM specifications WHERE identifier = :spec_id
]]

-- Check if a type uses hierarchical PID generation (composite types)
M.type_is_composite = [[
    SELECT is_composite FROM spec_object_types WHERE identifier = :type_ref
]]

-- Get composite-type objects ordered by file_seq for hierarchical numbering
M.composites_by_spec = [[
    SELECT o.id, o.pid, o.level, o.title_text, o.from_file, o.start_line
    FROM spec_objects o
    JOIN spec_object_types t ON o.type_ref = t.identifier
    WHERE o.specification_ref = :spec_id AND t.is_composite = 1
    ORDER BY o.file_seq
]]

-- Update object with auto-generated PID
M.update_object_pid = [[
    UPDATE spec_objects
    SET pid = :pid, pid_prefix = :prefix, pid_sequence = :seq, pid_auto_generated = 1
    WHERE id = :id
]]

-- ============================================================================
-- Object PIDs: Sequential (non-composite types)
-- ============================================================================

-- Get distinct type_refs that have objects in a specification
M.distinct_types_by_spec = [[
    SELECT DISTINCT type_ref FROM spec_objects
    WHERE specification_ref = :spec_id
]]

-- Get sibling objects of same type for pattern detection and PID generation
M.siblings_by_spec_type = [[
    SELECT id, pid, pid_prefix, pid_sequence, pid_auto_generated,
           title_text, from_file, start_line
    FROM spec_objects
    WHERE specification_ref = :spec_id AND type_ref = :type_ref
    ORDER BY file_seq
]]

return M
