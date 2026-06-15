-- Test oracle for VC-022: Type Definition Schema (host engine)
-- Verifies host schema defaults (long_name/counter_group fall back to id), enum
-- attribute registration, and that a missing schema.id is a LOUD register-time
-- error (HLR-EXT-011) -- not the legacy silent skip.

return function(_, _)
    local utils = require("type_loader_test_utils")
    local registry = require("contract.registry")
    local uv = require("luv")

    local root = uv.cwd()
    local valid_model = utils.unique_name("vc022_valid")
    local bad_model = utils.unique_name("vc022_bad")

    local ok, err = pcall(function()
        -- 1. A model of well-formed types: defaults + enum registration.
        local created, create_err = utils.create_model(root, valid_model, {
            ["objects/valid_object.lua"] = [[
                return {
                    kind = "object",
                    schema = {
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
            ["floats/minimal_float.lua"] = [[
                return { kind = "float", schema = { id = "VC022_FLOAT" } }
            ]],
            ["views/minimal_view.lua"] = [[
                return { kind = "view", schema = { id = "VC022_VIEW", materializer_type = "inline" } }
            ]],
            ["relations/minimal_relation.lua"] = [[
                return { kind = "relation", schema = { id = "VC022_REL", source_type_ref = "HLR", target_type_ref = "HLR" } }
            ]],
            ["specifications/minimal_spec.lua"] = [[
                return { kind = "specification", schema = { id = "VC022_SPEC" } }
            ]]
        })
        if not created then
            error("Failed to create valid model: " .. tostring(create_err))
        end

        local data, calls = utils.new_data_collector()
        local pipeline = { register_handler = function() end }

        utils.clear_loaded_model(valid_model)
        registry.new{ data = data, pipeline = pipeline }:load_model(valid_model)

        local identifiers = utils.identifiers_from_calls(calls)
        for _, identifier in ipairs({ "VC022_OBJ", "VC022_FLOAT", "VC022_VIEW", "VC022_REL", "VC022_SPEC" }) do
            if not identifiers[identifier] then
                error("Expected registered identifier missing: " .. identifier)
            end
        end

        -- Defaults: long_name and counter_group fall back to id.
        if identifiers["VC022_FLOAT"].long_name ~= "VC022_FLOAT" then
            error("Float long_name default should fall back to id")
        end
        if identifiers["VC022_FLOAT"].counter_group ~= "VC022_FLOAT" then
            error("Float counter_group default should fall back to id")
        end

        -- Enum values registered.
        local enum_high, enum_low = false, false
        for _, call in ipairs(calls) do
            local params = call.params or {}
            if params.datatype == "ENUM_PRIORITY" and params.key == "High" then enum_high = true end
            if params.datatype == "ENUM_PRIORITY" and params.key == "Low" then enum_low = true end
        end
        if not enum_high or not enum_low then
            error("Expected enum values (High, Low) were not registered")
        end

        -- 2. A type WITHOUT a schema.id is a loud register-time error.
        local created_bad, create_bad_err = utils.create_model(root, bad_model, {
            ["objects/missing_id.lua"] = [[
                return { kind = "object", schema = { long_name = "Missing Identifier Object" } }
            ]]
        })
        if not created_bad then
            error("Failed to create bad model: " .. tostring(create_bad_err))
        end

        local data_bad = { execute = function() end }
        local ok_bad, bad_err = pcall(function()
            utils.clear_loaded_model(bad_model)
            registry.new{ data = data_bad, pipeline = pipeline }:load_model(bad_model)
        end)
        if ok_bad then
            error("Expected a missing schema.id type to error loudly")
        end
        if not tostring(bad_err):find("schema.id", 1, true) then
            error("Missing-id error should name schema.id, got: " .. tostring(bad_err))
        end
    end)

    utils.clear_loaded_model(valid_model)
    utils.clear_loaded_model(bad_model)
    utils.remove_model(root, valid_model)
    utils.remove_model(root, bad_model)

    if not ok then
        return false, tostring(err)
    end
    return true
end
