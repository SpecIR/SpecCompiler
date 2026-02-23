---PID Auto-Generator for SpecCompiler.
---ANALYZE phase handler that generates PIDs for objects without explicit @PID.
---Runs BEFORE relation_analyzer so PIDs are available for resolution.
---
---Detects sibling patterns (prefix, format, max_seq) from explicit PIDs,
---then generates sequential PIDs for objects with pid IS NULL.
---Composite types get hierarchical PIDs qualified by spec PID (e.g., SRS-sec1.2.3).
---Specifications without explicit @PID get auto-generated PIDs from type_ref.
---
---@module pid_generator
local logger = require("infra.logger")
local pid_utils = require("pipeline.shared.pid_utils")
local Queries = require("db.queries")

local M = {
    name = "pid_generator",
    prerequisites = {}  -- Runs first in ANALYZE (before relation_analyzer)
}

---Auto-generate PIDs for specifications without explicit @PID.
---Uses type_ref as the PID base. If collision, increments: SRS, SRS-2, SRS-3, ...
---Must run before object PID generation since hierarchical PIDs depend on spec PIDs.
---@param data DataManager
---@return integer count Number of spec PIDs generated
local function generate_spec_pids(data)
    local specs_without_pid = data:query_all(Queries.pid.specs_without_pid)

    if not specs_without_pid or #specs_without_pid == 0 then return 0 end

    local generated = 0

    for _, spec in ipairs(specs_without_pid) do
        local base = spec.type_ref or spec.identifier
        local candidate = base
        local suffix = 2

        -- Check for collision with existing PIDs (explicit or previously auto-generated)
        while true do
            local existing = data:query_one(Queries.pid.spec_pid_exists,
                { pid = candidate })

            if not existing then break end

            candidate = base .. "-" .. tostring(suffix)
            suffix = suffix + 1
        end

        data:execute(Queries.pid.update_spec_pid,
            { pid = candidate, id = spec.identifier })

        logger.debug(string.format(
            "Auto-generated spec PID '%s' for specification '%s'",
            candidate, spec.identifier
        ))

        generated = generated + 1
    end

    return generated
end

---Generate hierarchical PIDs for composite-type objects based on header level.
---Produces PIDs qualified by spec PID (e.g., SRS-sec1.2.3).
---@param data DataManager
---@param spec_id string Specification identifier
---@return integer count Number of PIDs generated
local function generate_hierarchical_pids(data, spec_id)
    -- Fetch the spec PID (always present after generate_spec_pids runs)
    local spec = data:query_one(Queries.pid.spec_pid_by_id,
        { spec_id = spec_id })

    local spec_pid = spec and spec.pid or spec_id

    local composites = data:query_all(Queries.pid.composites_by_spec,
        { spec_id = spec_id })

    if not composites or #composites == 0 then return 0 end

    -- Find the minimum level (typically 2 for H2) to use as depth base
    local min_level = math.huge
    for _, obj in ipairs(composites) do
        if obj.level and obj.level < min_level then
            min_level = obj.level
        end
    end

    -- Hierarchical counters: counters[1] = top-level count, counters[2] = sub-level, etc.
    local counters = {}
    local generated = 0

    for _, sec in ipairs(composites) do
        if sec.pid and sec.pid ~= "" then
            -- Object has explicit PID; still track its level for hierarchy context
            -- but don't overwrite the author-provided PID
            goto next_section
        end

        local depth = (sec.level or min_level) - min_level + 1

        -- Truncate counters to current depth (going shallower resets deeper counters)
        for i = depth + 1, #counters do
            counters[i] = nil
        end

        -- Initialize or increment counter at current depth
        counters[depth] = (counters[depth] or 0) + 1

        -- Ensure all parent levels have counters (handle level gaps)
        for i = 1, depth - 1 do
            if not counters[i] then
                counters[i] = 1
            end
        end

        -- Build hierarchical PID qualified by spec PID: SRS-sec1.2.3
        local parts = {}
        for i = 1, depth do
            table.insert(parts, tostring(counters[i]))
        end
        local auto_pid = spec_pid .. "-sec" .. table.concat(parts, ".")

        data:execute(Queries.pid.update_object_pid, {
            id = sec.id,
            pid = auto_pid,
            prefix = 'sec',
            seq = counters[depth]
        })

        logger.debug(string.format(
            "Auto-generated PID '%s' for '%s' at %s:%d",
            auto_pid, sec.title_text or "", sec.from_file or "unknown", sec.start_line or 0
        ))

        generated = generated + 1

        ::next_section::
    end

    return generated
end

---Auto-generate PIDs for objects without explicit PIDs.
---Groups objects by (specification_ref, type_ref) to detect sibling patterns.
---Composite types use hierarchical numbering (sec1.2.3).
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_analyze(data, contexts, diagnostics)
    local total_generated = 0

    data:begin_transaction()

    -- Step 1: Auto-generate PIDs for specifications without explicit @PID
    -- Must run before hierarchical PID generation since those depend on spec PIDs
    local spec_pids_generated = generate_spec_pids(data)
    if spec_pids_generated > 0 then
        logger.info(string.format("Auto-generated %d specification PIDs", spec_pids_generated))
    end

    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        -- Get all type_refs that have objects in this spec
        local type_groups = data:query_all(Queries.pid.distinct_types_by_spec,
            { spec_id = spec_id })

        for _, group in ipairs(type_groups or {}) do
            local type_ref = group.type_ref

            -- Composite types get hierarchical PIDs (e.g., sec1.2.3)
            local type_info = data:query_one(Queries.pid.type_is_composite, { type_ref = type_ref })
            if type_info and type_info.is_composite == 1 then
                total_generated = total_generated + generate_hierarchical_pids(data, spec_id)
                goto next_group
            end

            -- Get all objects of this type, ordered by file_seq
            local siblings = data:query_all(Queries.pid.siblings_by_spec_type,
                { spec_id = spec_id, type_ref = type_ref })

            if not siblings or #siblings == 0 then goto next_group end

            -- Check if any objects need PIDs
            local needs_pid = false
            for _, sib in ipairs(siblings) do
                if not sib.pid or sib.pid == "" then
                    needs_pid = true
                    break
                end
            end

            if not needs_pid then goto next_group end

            -- Detect pattern from explicit-PID siblings
            local explicit_siblings = {}
            for _, sib in ipairs(siblings) do
                if sib.pid and sib.pid ~= "" then
                    local prefix, seq, fmt = pid_utils.parse_pid_pattern(sib.pid)
                    table.insert(explicit_siblings, {
                        pid_prefix = prefix,
                        pid_sequence = seq,
                        pid_format = fmt
                    })
                end
            end

            local prefix, format_str, max_seq, conflict = pid_utils.detect_sibling_pattern(explicit_siblings)

            -- If no pattern detected, use type_ref as prefix with default format
            if not prefix and not format_str then
                prefix = type_ref
                format_str = "%s-%03d"
                max_seq = 0
            end

            -- Generate PIDs for objects without explicit PID
            local next_seq = max_seq + 1
            for _, sib in ipairs(siblings) do
                if not sib.pid or sib.pid == "" then
                    local auto_pid = pid_utils.generate_next_pid(prefix, format_str, next_seq)

                    -- Parse the generated PID to get prefix/sequence
                    local gen_prefix, gen_seq, _ = pid_utils.parse_pid_pattern(auto_pid)

                    data:execute(Queries.pid.update_object_pid, {
                        id = sib.id,
                        pid = auto_pid,
                        prefix = gen_prefix,
                        seq = gen_seq
                    })

                    logger.debug(string.format(
                        "Auto-generated PID '%s' for '%s' at %s:%d",
                        auto_pid, sib.title_text or "", sib.from_file or "unknown", sib.start_line or 0
                    ))

                    next_seq = next_seq + 1
                    total_generated = total_generated + 1
                end
            end

            ::next_group::
        end
    end

    data:commit()

    if total_generated > 0 then
        logger.info(string.format("Auto-generated %d PIDs across all specifications", total_generated))
    end
end

return M
