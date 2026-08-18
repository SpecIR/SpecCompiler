---PID Auto-Generator for SpecCompiler.
---RESOLVE phase handler that generates PIDs for objects without explicit @PID.
---Runs BEFORE relation_resolver so PIDs are available for resolution.
---
---Uses each type's pid_prefix and pid_format for both schemes. Types with
---pid_scheme = "hierarchical" get per-type dotted PIDs qualified by spec PID
---(e.g., SRS-sec1.2.3); sequential types number independently per type.
---Specifications without explicit @PID get auto-generated PIDs from type_ref.
---
---@module pid_generator
local logger = require("infra.logger")
local pid_utils = require("pipeline.shared.pid_utils")
local Queries = require("db.queries")

local M = {
    name = "pid_generator",
    prerequisites = {}  -- Runs first in RESOLVE (before relation_resolver)
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

---Generate hierarchical PIDs for one hierarchical type based on header level.
---Produces PIDs qualified by spec PID (e.g., SRS-sec1.2.3). Each type keeps
---its own counter chain and its own pid_prefix/pid_format ("sec" / "%s%s"
---when the type declares none). Depth anchors to the structural constant:
---objects live at header level 2+, so level 2 = depth 1.
---@param data DataManager
---@param spec_id string Specification identifier
---@param type_ref string Object type identifier
---@param settings table Type row with pid_prefix / pid_format
---@return integer count Number of PIDs generated
local function generate_hierarchical_pids(data, spec_id, type_ref, settings)
    -- Fetch the spec PID (always present after generate_spec_pids runs)
    local spec = data:query_one(Queries.pid.spec_pid_by_id,
        { spec_id = spec_id })

    local spec_pid = spec and spec.pid or spec_id

    local objects = data:query_all(Queries.pid.hierarchical_objects_by_spec_type,
        { spec_id = spec_id, type_ref = type_ref })

    if not objects or #objects == 0 then return 0 end

    local prefix = settings.pid_prefix or "sec"
    local format_str = settings.pid_format or "%s%s"
    local warned_format = false

    -- Hierarchical counters: counters[1] = top-level count, counters[2] = sub-level, etc.
    local counters = {}
    local generated = 0

    for _, sec in ipairs(objects) do
        if sec.pid and sec.pid ~= "" then
            -- Object has explicit PID; don't overwrite the author-provided PID
            goto next_section
        end

        local depth = math.max((sec.level or 2) - 1, 1)

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

        -- Build the candidate PID; bump the counter past collisions with
        -- explicit author PIDs (e.g. an author-claimed SRS-sec3).
        local auto_pid
        while true do
            local parts = {}
            for i = 1, depth do
                table.insert(parts, tostring(counters[i]))
            end
            local dotted = table.concat(parts, ".")
            local ok, formatted = pcall(string.format, format_str, prefix, dotted)
            if not ok then
                if not warned_format then
                    logger.warn(string.format(
                        "Type %s: pid_format '%s' is not usable for hierarchical numbering "
                        .. "(needs two %%s slots); falling back to '%%s%%s'",
                        type_ref, format_str))
                    warned_format = true
                end
                formatted = prefix .. dotted
            end
            auto_pid = spec_pid .. "-" .. formatted

            local existing = data:query_one(Queries.pid.object_pid_exists,
                { spec_id = spec_id, pid = auto_pid })
            if not existing then break end
            counters[depth] = counters[depth] + 1
        end

        data:execute(Queries.pid.update_object_pid, {
            id = sec.id,
            pid = auto_pid,
            prefix = prefix,
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
---Uses the type's pid_prefix and pid_format; hierarchical-scheme types use
---per-type dotted numbering (sec1.2.3), all others sequential numbering.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_resolve(data, contexts, diagnostics)
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

            -- One settings row drives both schemes (is_composite = 1 stores
            -- pid_scheme = "hierarchical"); prefix/format are respected by both.
            local settings = data:query_one(Queries.pid.type_pid_settings,
                { type_ref = type_ref }) or {}

            if settings.is_composite == 1 then
                total_generated = total_generated
                    + generate_hierarchical_pids(data, spec_id, type_ref, settings)
                goto next_group
            end

            -- Get objects that need PIDs
            local objects = data:query_all(Queries.pid.objects_needing_pid,
                { spec_id = spec_id, type_ref = type_ref })

            if not objects or #objects == 0 then goto next_group end

            local prefix = settings.pid_prefix or type_ref
            local format_str = settings.pid_format or "%s-%03d"

            -- Find max existing sequence to avoid collisions
            local seq_row = data:query_one(Queries.pid.max_seq_by_spec_type,
                { spec_id = spec_id, type_ref = type_ref })
            local next_seq = (seq_row and seq_row.max_seq or 0) + 1

            -- Generate PIDs for objects without explicit PID; probe past
            -- collisions with explicit author PIDs that carry no sequence.
            for _, obj in ipairs(objects) do
                local auto_pid
                while true do
                    auto_pid = pid_utils.generate_next_pid(prefix, format_str, next_seq)
                    local existing = data:query_one(Queries.pid.object_pid_exists,
                        { spec_id = spec_id, pid = auto_pid })
                    if not existing then break end
                    next_seq = next_seq + 1
                end

                data:execute(Queries.pid.update_object_pid, {
                    id = obj.id,
                    pid = auto_pid,
                    prefix = prefix,
                    seq = next_seq
                })

                logger.debug(string.format(
                    "Auto-generated PID '%s' for '%s' at %s:%d",
                    auto_pid, obj.title_text or "", obj.from_file or "unknown", obj.start_line or 0
                ))

                next_seq = next_seq + 1
                total_generated = total_generated + 1
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
