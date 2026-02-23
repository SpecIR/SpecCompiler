-- Test oracle for VC-020: Model Directory Structure
-- Verifies all KNOWN_CATEGORIES are discovered and loaded.

return function(_, _)
    local utils = require("type_loader_test_utils")
    local type_loader = require("core.type_loader")
    local uv = require("luv")

    local root = uv.cwd()
    local model_name = utils.unique_name("vc020_model")
    local ok, err = pcall(function()
        local created, create_err = utils.create_model(root, model_name, {
            ["objects/object_vc020.lua"] = [[
                return { object = { id = "VC020_OBJ", long_name = "VC020 Object" } }
            ]],
            ["floats/float_vc020.lua"] = [[
                return { float = { id = "VC020_FLOAT", long_name = "VC020 Float", counter_group = "vc020_counter" } }
            ]],
            ["views/view_vc020.lua"] = [[
                return { view = { id = "VC020_VIEW", long_name = "VC020 View", materializer_type = "inline" } }
            ]],
            ["relations/relation_vc020.lua"] = [[
                return {
                    relation = {
                        id = "VC020_REL",
                        long_name = "VC020 Relation",
                        source_type_ref = "HLR",
                        target_type_ref = "HLR"
                    }
                }
            ]],
            ["specifications/spec_vc020.lua"] = [[
                return { specification = { id = "VC020_SPEC", long_name = "VC020 Spec" } }
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
            "VC020_OBJ",
            "VC020_FLOAT",
            "VC020_VIEW",
            "VC020_REL",
            "VC020_SPEC"
        }

        for _, identifier in ipairs(expected) do
            if not identifiers[identifier] then
                error("Expected type identifier not loaded: " .. identifier)
            end
        end

        if identifiers["VC020_FLOAT"].counter_group ~= "vc020_counter" then
            error("Float counter_group mismatch for VC020_FLOAT")
        end
        if identifiers["VC020_VIEW"].materializer_type ~= "inline" then
            error("View materializer_type mismatch for VC020_VIEW")
        end
        if identifiers["VC020_REL"].source_type_ref ~= "HLR" then
            error("Relation source_type_ref mismatch for VC020_REL")
        end
        if identifiers["VC020_SPEC"].long_name ~= "VC020 Spec" then
            error("Specification long_name mismatch for VC020_SPEC")
        end
    end)

    utils.clear_loaded_model(model_name)
    utils.remove_model(root, model_name)

    if not ok then
        return false, tostring(err)
    end
    return true
end
