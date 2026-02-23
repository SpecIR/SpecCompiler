---Test fixture with unsupported return payload.
---Used to exercise data_loader unknown-format warning path.
---@module test_fixtures.bad_return
local M = {}

function M.generate()
    return {
        unsupported = true
    }
end

return M
