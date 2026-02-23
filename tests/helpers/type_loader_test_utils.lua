-- Utilities for type_loader-focused E2E Lua oracles.

local uv = require("luv")

local M = {}

math.randomseed(tonumber(uv.hrtime() % 2147483647))

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function escape_lua_pattern(value)
    return tostring(value):gsub("([^%w])", "%%%1")
end

function M.unique_name(prefix)
    return string.format("%s_%d_%06d", prefix, os.time(), math.random(0, 999999))
end

function M.ensure_dir(path)
    os.execute("mkdir -p " .. shell_quote(path))
end

function M.remove_path(path)
    os.execute("rm -rf " .. shell_quote(path))
end

function M.write_file(path, content)
    local dir = path:match("(.+)/[^/]+$")
    if dir then
        M.ensure_dir(dir)
    end
    local handle, err = io.open(path, "w")
    if not handle then
        return false, err
    end
    handle:write(content)
    handle:close()
    return true
end

function M.create_model(root, model_name, files)
    local base = root .. "/models/" .. model_name .. "/types"
    for relative_path, content in pairs(files) do
        local ok, err = M.write_file(base .. "/" .. relative_path, content)
        if not ok then
            return nil, err
        end
    end
    return base
end

function M.remove_model(root, model_name)
    M.remove_path(root .. "/models/" .. model_name)
end

function M.clear_loaded_model(model_name)
    local prefix = "models." .. model_name
    local pattern = "^" .. escape_lua_pattern(prefix)
    for module_name, _ in pairs(package.loaded) do
        if module_name:match(pattern) then
            package.loaded[module_name] = nil
        end
    end
end

function M.with_spechome(path, fn)
    local previous = uv.os_getenv("SPECCOMPILER_HOME")
    uv.os_setenv("SPECCOMPILER_HOME", path)

    local ok, a, b, c = xpcall(fn, debug.traceback)

    if previous then
        uv.os_setenv("SPECCOMPILER_HOME", previous)
    else
        uv.os_unsetenv("SPECCOMPILER_HOME")
    end

    if not ok then
        error(a, 0)
    end
    return a, b, c
end

function M.with_package_path(prefixes, fn)
    local original = package.path
    local parts = {}
    for _, prefix in ipairs(prefixes or {}) do
        table.insert(parts, prefix)
    end
    if #parts > 0 then
        package.path = table.concat(parts, ";") .. ";" .. original
    end

    local ok, a, b, c = xpcall(fn, debug.traceback)
    package.path = original

    if not ok then
        error(a, 0)
    end
    return a, b, c
end

function M.new_data_collector()
    local calls = {}
    local data = {
        execute = function(_, query, params)
            table.insert(calls, { query = query, params = params })
        end
    }
    return data, calls
end

function M.identifiers_from_calls(calls)
    local identifiers = {}
    for _, call in ipairs(calls or {}) do
        local params = call.params or {}
        if params.identifier then
            identifiers[params.identifier] = params
        end
    end
    return identifiers
end

return M
