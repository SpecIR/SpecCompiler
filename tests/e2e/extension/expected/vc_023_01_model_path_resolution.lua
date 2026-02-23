-- Test oracle for VC-023: Model Path Resolution
-- Verifies SPECCOMPILER_HOME precedence, cwd fallback, and not-found failure mode.

return function(_, _)
    local utils = require("type_loader_test_utils")
    local type_loader = require("core.type_loader")
    local uv = require("luv")

    local root = uv.cwd()
    local home_root = "/tmp/" .. utils.unique_name("vc023_home")

    local prefer_model = utils.unique_name("vc023_prefer")
    local fallback_model = utils.unique_name("vc023_fallback")
    local missing_model = utils.unique_name("vc023_missing")

    local ok, err = pcall(function()
        local created_prefer_cwd, err_prefer_cwd = utils.create_model(root, prefer_model, {
            ["objects/cwd_only.lua"] = [[
                return { object = { id = "VC023_CWD_SELECTED", long_name = "CWD selected model" } }
            ]]
        })
        if not created_prefer_cwd then
            error("Failed to create cwd prefer-model fixture: " .. tostring(err_prefer_cwd))
        end

        local created_prefer_home, err_prefer_home = utils.create_model(home_root, prefer_model, {
            ["objects/home_only.lua"] = [[
                return { object = { id = "VC023_HOME_SELECTED", long_name = "HOME selected model" } }
            ]]
        })
        if not created_prefer_home then
            error("Failed to create home prefer-model fixture: " .. tostring(err_prefer_home))
        end

        local created_fallback_cwd, err_fallback_cwd = utils.create_model(root, fallback_model, {
            ["objects/fallback_only.lua"] = [[
                return { object = { id = "VC023_CWD_FALLBACK", long_name = "CWD fallback model" } }
            ]]
        })
        if not created_fallback_cwd then
            error("Failed to create cwd fallback fixture: " .. tostring(err_fallback_cwd))
        end

        utils.with_spechome(home_root, function()
            utils.with_package_path({
                root .. "/?.lua",
                root .. "/?/init.lua",
                home_root .. "/?.lua",
                home_root .. "/?/init.lua"
            }, function()
                local pipeline = { register_handler = function() end }

                -- Case 1: model exists in SPECCOMPILER_HOME and cwd -> SPECCOMPILER_HOME wins.
                local data_prefer, calls_prefer = utils.new_data_collector()
                utils.clear_loaded_model(prefer_model)
                type_loader.load_model(data_prefer, pipeline, prefer_model)
                local prefer_ids = utils.identifiers_from_calls(calls_prefer)

                if not prefer_ids["VC023_HOME_SELECTED"] then
                    error("Expected SPECCOMPILER_HOME model to be loaded first")
                end
                if prefer_ids["VC023_CWD_SELECTED"] then
                    error("CWD model should not be selected when SPECCOMPILER_HOME has the model")
                end

                -- Case 2: model missing in SPECCOMPILER_HOME but exists in cwd -> cwd fallback.
                local data_fallback, calls_fallback = utils.new_data_collector()
                utils.clear_loaded_model(fallback_model)
                type_loader.load_model(data_fallback, pipeline, fallback_model)
                local fallback_ids = utils.identifiers_from_calls(calls_fallback)

                if not fallback_ids["VC023_CWD_FALLBACK"] then
                    error("Expected cwd fallback model to load when SPECCOMPILER_HOME misses model")
                end

                -- Case 3: missing in both locations -> hard failure.
                local data_missing = { execute = function() end }
                local ok_missing, missing_err = pcall(function()
                    utils.clear_loaded_model(missing_model)
                    type_loader.load_model(data_missing, pipeline, missing_model)
                end)
                if ok_missing then
                    error("Expected missing model load to fail")
                end
                if not tostring(missing_err):match("Failed to locate model") then
                    error("Unexpected missing-model error: " .. tostring(missing_err))
                end
            end)
        end)
    end)

    utils.clear_loaded_model(prefer_model)
    utils.clear_loaded_model(fallback_model)
    utils.clear_loaded_model(missing_model)
    utils.remove_model(root, prefer_model)
    utils.remove_model(root, fallback_model)
    utils.remove_path(home_root)

    if not ok then
        return false, tostring(err)
    end
    return true
end
