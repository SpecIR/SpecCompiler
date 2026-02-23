---Test fixture view for Sankey injection path.
---Returns nodes/links so data_loader injects series[1].data and series[1].links.
---@module test_fixtures.sankey_edges
local M = {}

function M.generate(params)
    return {
        data = {
            { name = "Start" },
            { name = "End" }
        },
        links = {
            { source = "Start", target = "End", value = tonumber(params.value) or 1 }
        }
    }
end

return M
