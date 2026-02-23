---Spec Objects Handler for SpecCompiler.
---Creates spec_objects from L2+ headers (parsed by specifications handler).
---Uses INTEGER PRIMARY KEY (auto-assigned by SQLite).
---Generates unified labels via label_utils.
---
---@module spec_objects
local logger = require("infra.logger")
local Queries = require("db.queries")
local label_utils = require("pipeline.shared.label_utils")
local hash_utils = require("infra.hash_utils")

local M = {
    name = "spec_objects",
    prerequisites = {"specifications"}  -- Needs parsed_headers from specifications
}

---BATCH MODE: Process ALL documents in a single transaction.
---@param data DataManager
---@param contexts table Array of Context objects
---@param diagnostics Diagnostics
function M.on_initialize(data, contexts, diagnostics)
    local all_objects = {}
    local spec_ids = {}
    local total_count = 0

    -- Track existing labels per spec for uniqueness
    local labels_by_spec = {}

    -- Phase 1: Collect all spec objects from ALL documents (CPU-bound)
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"
        local source_path = ctx.source_path or "unknown"
        local parsed_headers = ctx.parsed_headers

        if parsed_headers then
            table.insert(spec_ids, spec_id)
            if not labels_by_spec[spec_id] then
                labels_by_spec[spec_id] = {}
            end

            for _, parsed in ipairs(parsed_headers) do
                local header = parsed.header

                if header.level > 1 then
                    local actual_file = header.source_file or source_path

                    -- Validate title is non-empty (mandatory)
                    if not parsed.title or parsed.title:match("^%s*$") then
                        diagnostics:add_warning(
                            actual_file,
                            header.line,
                            string.format("Object at %s:%d has no title. Every spec object must have a title.",
                                actual_file, header.line or 0)
                        )
                    end

                    -- Compute content_sha for change detection (not a key)
                    local content_key = actual_file .. ":" .. (header.line or 0) .. ":" .. header.title_text
                    local content_sha = hash_utils.sha1(content_key)

                    -- Compute unified label: {type_lower}:{title_slug}
                    local base_label = label_utils.compute_object_label(parsed.type_ref, parsed.title)
                    local label = nil
                    if base_label then
                        label = label_utils.make_unique_label(base_label, labels_by_spec[spec_id])
                        labels_by_spec[spec_id][label] = true
                    end

                    table.insert(all_objects, {
                        content_sha = content_sha,
                        specification_ref = spec_id,
                        type_ref = parsed.type_ref,
                        from_file = actual_file,
                        file_seq = parsed.seq,
                        pid = parsed.pid,
                        pid_prefix = parsed.pid_prefix,
                        pid_sequence = parsed.pid_sequence,
                        pid_auto_generated = 0,
                        title_text = parsed.title or "",
                        label = label,
                        level = header.level,
                        start_line = header.line,
                        end_line = parsed.end_line,
                        ast = parsed.ast_json
                    })
                    total_count = total_count + 1
                end
            end
        end
    end

    -- Phase 2: Single transaction for ALL database operations
    if #spec_ids > 0 then
        data:begin_transaction()

        -- Bulk DELETE for all specs
        for _, spec_id in ipairs(spec_ids) do
            data:execute(Queries.content.delete_objects_by_spec, { spec_id = spec_id })
        end

        -- Insert all objects in single transaction
        -- Duplicate PID detection is handled by view_object_duplicate_pid proof in VERIFY phase.
        for _, obj in ipairs(all_objects) do
            data:execute(Queries.content.insert_object, obj)
        end

        data:commit()
    end

    -- Log summary
    if total_count > 0 then
        logger.info(string.format("Created %d total spec objects across %d documents", total_count, #spec_ids))
    end
end

return M
