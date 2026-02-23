-- Test oracle for VC-021: Handler Registration Interface
-- Verifies successful handler export registration and strict registration failures.

return function(_, _)
    local utils = require("type_loader_test_utils")
    local type_loader = require("core.type_loader")
    local uv = require("luv")

    local root = uv.cwd()
    local success_model = utils.unique_name("vc021_ok_model")
    local failure_model = utils.unique_name("vc021_bad_model")
    local ok, err = pcall(function()
        local created_ok, create_ok_err = utils.create_model(root, success_model, {
            ["objects/object_with_handler.lua"] = [[
                return {
                    object = { id = "VC021_OBJ_OK", long_name = "VC021 Object OK" },
                    handler = {
                        name = "vc021_handler_ok",
                        prerequisites = { "initialize" },
                        on_initialize = function() end
                    }
                }
            ]],
            ["objects/object_without_handler.lua"] = [[
                return {
                    object = { id = "VC021_OBJ_NO_HANDLER", long_name = "No Handler Object" }
                }
            ]]
        })
        if not created_ok then
            error("Failed to create success model: " .. tostring(create_ok_err))
        end

        local created_bad, create_bad_err = utils.create_model(root, failure_model, {
            ["objects/object_with_invalid_handler.lua"] = [[
                return {
                    object = { id = "VC021_OBJ_BAD", long_name = "VC021 Object BAD" },
                    handler = {
                        name = "vc021_handler_bad",
                        on_initialize = function() end
                    }
                }
            ]]
        })
        if not created_bad then
            error("Failed to create failure model: " .. tostring(create_bad_err))
        end

        local data_ok = { execute = function() end }
        local registered_handlers = {}
        local strict_pipeline = {
            register_handler = function(_, handler)
                if not handler or not handler.name then
                    error("handler missing name")
                end
                if type(handler.prerequisites) ~= "table" then
                    error("handler prerequisites missing")
                end
                table.insert(registered_handlers, handler)
            end
        }

        utils.clear_loaded_model(success_model)
        type_loader.load_model(data_ok, strict_pipeline, success_model)

        if #registered_handlers ~= 1 then
            error("Expected exactly one registered handler, got " .. tostring(#registered_handlers))
        end
        if registered_handlers[1].name ~= "vc021_handler_ok" then
            error("Unexpected registered handler name: " .. tostring(registered_handlers[1].name))
        end
        if type(registered_handlers[1].prerequisites) ~= "table"
            or registered_handlers[1].prerequisites[1] ~= "initialize" then
            error("Registered handler prerequisites mismatch")
        end

        local data_bad = { execute = function() end }
        local ok_bad, bad_err = pcall(function()
            utils.clear_loaded_model(failure_model)
            type_loader.load_model(data_bad, strict_pipeline, failure_model)
        end)
        if ok_bad then
            error("Expected invalid handler registration to fail")
        end
        if not tostring(bad_err):match("handler prerequisites missing") then
            error("Unexpected invalid handler error: " .. tostring(bad_err))
        end
    end)

    utils.clear_loaded_model(success_model)
    utils.clear_loaded_model(failure_model)
    utils.remove_model(root, success_model)
    utils.remove_model(root, failure_model)

    if not ok then
        return false, tostring(err)
    end
    return true
end
