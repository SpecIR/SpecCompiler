---Shared helpers for AsciiMath → MathML → native pandoc.Math conversion.
---@module math_render_utils

local M = {}

-- Try loading the luaamath native extension from known paths.
local function try_load_amath()
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

-- Normalize MathML to standard Unicode math symbols.
local function normalize_mathml(mathml)
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

    local amath = try_load_amath()
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

    return normalize_mathml(mathml), nil
end

---Parse a MathML fragment into a native pandoc.Math element.
---Uses pandoc.read with the "html" reader, which delegates to texmath
---(MathML → TeX). Pandoc's writers then emit format-appropriate output:
---OMML for DOCX, MathML/MathJax/etc. for HTML, TeX for LaTeX.
---@param mathml string MathML string including <math …>…</math>
---@param display_mode string "block"|"inline"
---@return table|nil pandoc.Math element, or nil on parse failure
function M.mathml_to_pandoc_math(mathml, display_mode)
    if not mathml or mathml == "" then return nil end
    local wrapped = "<p>" .. mathml .. "</p>"
    local ok, doc = pcall(pandoc.read, wrapped, "html")
    if not ok or not doc or not doc.blocks or #doc.blocks == 0 then
        return nil
    end
    local para = doc.blocks[1]
    if not para.content then return nil end
    for _, inline in ipairs(para.content) do
        if inline.t == "Math" then
            local mathtype = display_mode == "block" and "DisplayMath" or "InlineMath"
            return pandoc.Math(mathtype, inline.text)
        end
    end
    return nil
end

return M
