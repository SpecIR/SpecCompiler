---Shared helpers for AsciiMath and MathML/OMML rendering.
---@module math_render_utils

local task_runner = require("infra.process.task_runner")
local hash_utils = require("infra.hash_utils")

local M = {}

local RENDER_SCRIPT = "mml2omml.ts"

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

---Stable content hash via hash_utils (pandoc.sha1 with pure-Lua fallback).
---@param content string
---@return string
function M.hash_content(content)
    return hash_utils.sha1(content)
end

---Find mml2omml script or compiled binary.
---@param speccompiler_home string|nil
---@return string|nil
---@return boolean
function M.find_render_script(speccompiler_home)
    local candidates = {}
    local speccompiler_dist = os.getenv("SPECCOMPILER_DIST")

    -- Check SPECCOMPILER_DIST first (where binaries live in dist/ layout)
    if speccompiler_dist then
        candidates[#candidates + 1] = { path = speccompiler_dist .. "/bin/mml2omml", compiled = true }
    end

    if speccompiler_home then
        candidates[#candidates + 1] = { path = speccompiler_home .. "/bin/mml2omml", compiled = true }
        candidates[#candidates + 1] = { path = speccompiler_home .. "/src/tools/" .. RENDER_SCRIPT, compiled = false }
        candidates[#candidates + 1] = { path = speccompiler_home .. "/src/utils/" .. RENDER_SCRIPT, compiled = false }
        candidates[#candidates + 1] = { path = speccompiler_home .. "/scripts/" .. RENDER_SCRIPT, compiled = false }
    end

    candidates[#candidates + 1] = { path = "./bin/mml2omml", compiled = true }
    candidates[#candidates + 1] = { path = "./dist/bin/mml2omml", compiled = true }
    candidates[#candidates + 1] = { path = "./src/tools/" .. RENDER_SCRIPT, compiled = false }
    candidates[#candidates + 1] = { path = "./src/utils/" .. RENDER_SCRIPT, compiled = false }
    candidates[#candidates + 1] = { path = "scripts/" .. RENDER_SCRIPT, compiled = false }
    candidates[#candidates + 1] = { path = "../scripts/" .. RENDER_SCRIPT, compiled = false }

    for _, candidate in ipairs(candidates) do
        if file_exists(candidate.path) then
            return candidate.path, candidate.compiled
        end
    end

    return nil, false
end

---Validate runtime requirements for the selected renderer.
---@param is_compiled boolean
---@return boolean ok
---@return string|nil error
function M.ensure_runtime(is_compiled)
    if is_compiled then
        return true, nil
    end
    if task_runner.command_exists("deno") then
        return true, nil
    end
    return false, "Deno command not found in PATH"
end

---Build the process command for MathML→OMML conversion.
---@param render_script string
---@param is_compiled boolean
---@param input_file string
---@return string cmd
---@return table args
function M.build_render_command(render_script, is_compiled, input_file)
    if is_compiled then
        return render_script, { input_file }
    end
    return "deno", { "run", "--allow-read", render_script, input_file }
end

---Try loading the luaamath native extension.
---@return table|nil
function M.try_load_amath()
    local speccompiler_home = os.getenv("SPECCOMPILER_HOME") or "."
    local speccompiler_dist = os.getenv("SPECCOMPILER_DIST") or speccompiler_home
    local paths = {
        speccompiler_home .. "/vendor/luaamath.so",
        speccompiler_dist .. "/vendor/luaamath.so",
        "./vendor/luaamath.so",
        "/usr/local/lib/lua/5.4/luaamath.so",
        "./lib/luaamath.so",
    }
    for _, path in ipairs(paths) do
        local loader = package.loadlib(path, "luaopen_amath")
        if loader then
            local ok, amath = pcall(loader)
            if ok then
                return amath
            end
        end
    end
    -- Fallback: try standard require path (uses LUA_CPATH)
    local ok, amath = pcall(require, "luaamath")
    if ok then return amath end
    return nil
end

---Normalize MathML to use standard Unicode math symbols.
---@param mathml string
---@return string
function M.normalize_mathml(mathml)
    mathml = mathml:gsub("Σ", "∑")
    mathml = mathml:gsub("Π", "∏")
    return mathml
end

---Convert AsciiMath input to normalized MathML.
---@param raw_content string
---@param display_mode string "block"|"inline"
---@return string|nil
---@return string|nil
function M.asciimath_to_mathml(raw_content, display_mode)
    local asciimath = (raw_content or ""):match("^%s*(.-)%s*$")
    if asciimath == "" then
        return nil, "Empty math content"
    end

    local amath = M.try_load_amath()
    if not amath or not amath.to_mathml then
        return nil, "luaamath library not available"
    end

    local ok, mathml = pcall(amath.to_mathml, asciimath)
    if not ok or not mathml then
        return nil, "AsciiMath conversion failed: " .. tostring(mathml)
    end

    if not mathml:match("<math") then
        mathml = string.format(
            '<math xmlns="http://www.w3.org/1998/Math/MathML" display="%s"><mrow>%s</mrow></math>',
            display_mode or "block",
            mathml
        )
    end

    return M.normalize_mathml(mathml), nil
end

return M
