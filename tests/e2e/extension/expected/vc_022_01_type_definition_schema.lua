-- Test oracle for VC-022: Type Definition Schema
-- Verifies schema defaults, enum attribute registration, and invalid-type skipping.

return function(_, _)
    local utils = require("type_loader_test_utils")
    local type_loader = require("core.type_loader")
    local uv = require("luv")

    local root = uv.cwd()
    local model_name = utils.unique_name("vc022_model")
    local ok, err = pcall(function()
        local created, create_err = utils.create_model(root, model_name, {
            ["objects/valid_object.lua"] = [[
                return {
                    object = {
                        id = "VC022_OBJ",
                        long_name = "VC022 Object",
                        attributes = {
                            {
                                name = "priority",
                                datatype_ref = "ENUM_PRIORITY",
                                type = "ENUM",
                                values = { "High", "Low" }
                            }
                        }
                    }
                }
            ]],
            ["objects/missing_id.lua"] = [[
                return {
                    object = {
                        long_name = "Missing Identifier Object"
                    }
                }
            ]],
            ["floats/minimal_float.lua"] = [[
                return {
                    float = {
                        id = "VC022_FLOAT"
                    }
                }
            ]],
            ["views/minimal_view.lua"] = [[
                return {
                    view = {
                        id = "VC022_VIEW",
                        materializer_type = "inline"
                    }
                }
            ]],
            ["relations/minimal_relation.lua"] = [[
                return {
                    relation = {
                        id = "VC022_REL",
                        source_type_ref = "HLR",
                        target_type_ref = "HLR"
                    }
                }
            ]],
            ["specifications/minimal_spec.lua"] = [[
                return {
                    specification = {
                        id = "VC022_SPEC"
                    }
                }
            ]]
        })
        if not created then
            error("Failed to create test model: " .. tostring(create_err))
        end

        local data, calls = utils.new_data_collector()
        local pipeline = { register_handler = function() end }

        utils.clear_loaded_model(model_name)
        type_loader.load_model(data, pipeline, model_name)

        local identifiers = utils.identifiers_from_calls(calls)

        local expected = {
            "VC022_OBJ",
            "VC022_FLOAT",
            "VC022_VIEW",
            "VC022_REL",
            "VC022_SPEC"
        }

        for _, identifier in ipairs(expected) do
            if not identifiers[identifier] then
                error("Expected registered identifier missing: " .. identifier)
            end
        end

        if identifiers["Missing Identifier Object"] then
            error("Invalid object without id must not be registered")
        end

        if identifiers["VC022_FLOAT"].long_name ~= "VC022_FLOAT" then
            error("Float long_name default should fall back to id")
        end
        if identifiers["VC022_FLOAT"].counter_group ~= "VC022_FLOAT" then
            error("Float counter_group default should fall back to id")
        end

        local enum_high = false
        local enum_low = false
        for _, call in ipairs(calls) do
            local params = call.params or {}
            if params.datatype == "ENUM_PRIORITY" and params.key == "High" then
                enum_high = true
            end
            if params.datatype == "ENUM_PRIORITY" and params.key == "Low" then
                enum_low = true
            end
        end

        if not enum_high or not enum_low then
            error("Expected enum values (High, Low) were not registered")
        end
    end)

    utils.clear_loaded_model(model_name)
    utils.remove_model(root, model_name)

    if not ok then
        return false, tostring(err)
    end
    return true
end
