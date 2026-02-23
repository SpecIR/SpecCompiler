---Float Numbering for SpecCompiler.
---Assigns sequential numbers to floats per specification, grouped by counter_group.
---Runs in TRANSFORM phase so numbers are available for link rewriting.
---
---@module float_numbering
local Queries = require("db.queries")

local M = {
    name = "float_numbering",
    prerequisites = {}
}

---Assign sequential numbers to floats per specification, grouped by counter_group.
---Types with the same counter_group share numbering (e.g., FIGURE, CHART, PLANTUML).
---@param data DataManager
---@param contexts table Array of Context objects
---@param log table Logger
local function assign_float_numbers(data, contexts, log)
    for _, ctx in ipairs(contexts) do
        local spec_id = ctx.spec_id or "default"

        local counter_groups = data:query_all(Queries.content.distinct_counter_groups_by_spec,
            { spec_id = spec_id })

        for _, group_row in ipairs(counter_groups or {}) do
            local counter_group = group_row.counter_group

            -- Get all floats in this counter_group that have captions, ordered by file_seq
            -- Floats without captions (e.g., revision-sheet) are excluded from numbering
            local floats = data:query_all(Queries.content.floats_by_counter_group_by_spec,
                { counter_group = counter_group, spec_id = spec_id })

            -- Assign numbers
            for i, float in ipairs(floats or {}) do
                data:execute(Queries.content.update_float_number, {
                    number = i,
                    id = float.id
                })
            end

            if #(floats or {}) > 0 then
                log.debug("Numbered %d floats in counter_group %s for %s", #floats, counter_group, spec_id)
            end
        end
    end
end

---TRANSFORM phase hook: assign float numbers before link rewriting.
function M.on_transform(data, contexts, _diagnostics)
    local log = contexts[1] and contexts[1].log
    if not log then return end
    assign_float_numbers(data, contexts, log)
end

return M
