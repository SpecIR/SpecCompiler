-- Test oracle for VC-002: Handler Registration
-- Verifies register_handler contract checks for required fields and duplicates.

return function(_, _)
    local pipeline_mod = require("core.pipeline")

    local function nop() end

    local function new_pipeline()
        return pipeline_mod.new({
            log = { debug = nop, info = nop, warn = nop, error = nop },
            diagnostics = { errors = {}, has_errors = function() return false end },
            data = {},
            validation = {},
            project_info = {}
        })
    end

    local p = new_pipeline()

    local ok_missing_name, err_missing_name = pcall(function()
        p:register_handler({ prerequisites = {} })
    end)
    if ok_missing_name then
        return false, "Expected missing name registration to fail"
    end
    if not tostring(err_missing_name):match("Handler must have a 'name' field") then
        return false, "Unexpected missing-name error: " .. tostring(err_missing_name)
    end

    -- `prerequisites` is optional: handlers that carry only decorated per-item
    -- callbacks (e.g. on_render_Link) don't participate in phase ordering, so
    -- they need no prereqs. Registration defaults the field to an empty list.
    local handler_without_prereq = { name = "handler_without_prereq" }
    local ok_missing_prereq, err_missing_prereq = pcall(function()
        p:register_handler(handler_without_prereq)
    end)
    if not ok_missing_prereq then
        return false, "Expected missing prerequisites to default to {}, got error: "
            .. tostring(err_missing_prereq)
    end
    if type(handler_without_prereq.prerequisites) ~= "table"
        or #handler_without_prereq.prerequisites ~= 0 then
        return false, "Expected prerequisites to default to empty table"
    end

    p:register_handler({
        name = "dup_handler",
        prerequisites = {},
        on_initialize = function() end
    })

    local ok_duplicate, err_duplicate = pcall(function()
        p:register_handler({
            name = "dup_handler",
            prerequisites = {},
            on_initialize = function() end
        })
    end)
    if ok_duplicate then
        return false, "Expected duplicate handler registration to fail"
    end
    if not tostring(err_duplicate):match("Handler already registered: dup_handler") then
        return false, "Unexpected duplicate-handler error: " .. tostring(err_duplicate)
    end

    return true
end
