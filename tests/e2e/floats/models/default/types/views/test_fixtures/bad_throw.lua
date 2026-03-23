---Test fixture that raises at runtime.
---Used to exercise data_loader generate() error path.
---@module test_fixtures.bad_throw
local M = {}

function M.generate()
    error("intentional data loader fixture failure")
end

return M
