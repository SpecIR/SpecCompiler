---Gaussian Distribution view type module.
---Handles `gauss:` inline code syntax for generating Gaussian distribution data.
---
---Syntax:
---  `gauss:`                        - Default gaussian (mean=0, sigma=1)
---  `gauss: mean=0 sigma=2`         - Custom parameters
---  `gauss: xmin=-5 xmax=5 n=100`   - Custom range and points
---
---Parameters:
---  mean: mean of distribution (default: 0)
---  sigma/stddev: standard deviation (default: 1)
---  xmin: minimum x value (default: -3)
---  xmax: maximum x value (default: 3)
---  points/n: number of points (default: 61)
---
---Returns ECharts dataset format for charts, or summary for inline use.
---
---Uses the unified INITIALIZE -> TRANSFORM -> EMIT pattern:
---  - INITIALIZE: Not needed (computes at emit time)
---  - TRANSFORM: Not needed (computes at emit time)
---  - EMIT: Compute distribution, return data
---
---@module gauss
local M = {}

M.view = {
    id = "GAUSS",
    long_name = "Gaussian Distribution",
    description = "Gaussian/Normal distribution curve data",
    inline_prefix = "gauss",
    aliases = { "gaussian", "normal" },
}

-- ============================================================================
-- Parsing
-- ============================================================================

---Parse Gaussian parameters from syntax.
---@param text string Parameter text after "gauss:"
---@return table params Parsed parameters
local function parse_params(text)
    local params = {}
    if not text or text == "" then
        return params
    end

    -- Parse key=value pairs
    for key, value in text:gmatch("(%w+)%s*=%s*([%d%.%-]+)") do
        local num = tonumber(value)
        if num then
            if key == "mean" then
                params.mean = num
            elseif key == "sigma" or key == "stddev" then
                params.sigma = num
            elseif key == "xmin" then
                params.xmin = num
            elseif key == "xmax" then
                params.xmax = num
            elseif key == "points" or key == "n" then
                params.points = math.floor(num)
            end
        end
    end

    return params
end

local prefix_matcher = require("pipeline.shared.prefix_matcher")
local match_gauss_code = prefix_matcher.from_decl(M.view)

-- ============================================================================
-- Data Generation
-- ============================================================================

---Calculate the Gaussian/Normal distribution PDF value.
---@param x number Input value
---@param mean number Mean of distribution
---@param sigma number Standard deviation
---@return number y PDF value at x
local function gaussian_pdf(x, mean, sigma)
    local coeff = 1 / (sigma * math.sqrt(2 * math.pi))
    local exponent = -((x - mean) ^ 2) / (2 * sigma ^ 2)
    return coeff * math.exp(exponent)
end

---Generate Gaussian distribution curve data.
---@param params table Parameters
---@param data DataManager Database instance (unused for this view)
---@param spec_id string Specification identifier (unused for this view)
---@return table dataset ECharts dataset format {source = {{header}, {x, y}, ...}}
function M.generate(params, data, spec_id)
    params = params or {}
    local mean = params.mean or 0
    local sigma = params.sigma or 1
    local xmin = params.xmin or -3
    local xmax = params.xmax or 3
    local points = params.points or 61

    local source = { {"x", "y"} }
    local step = (xmax - xmin) / (points - 1)

    for i = 0, points - 1 do
        local x = xmin + i * step
        local y = gaussian_pdf(x, mean, sigma)
        -- Round to reasonable precision
        x = math.floor(x * 1000 + 0.5) / 1000
        y = math.floor(y * 10000 + 0.5) / 10000
        table.insert(source, {x, y})
    end

    return { source = source }
end

-- ============================================================================
-- Handler
-- ============================================================================

M.handler = {
    name = "gauss_handler",
    prerequisites = {},

    ---EMIT: Render inline Code elements with gauss: syntax.
    ---For inline use, returns a text summary of the parameters.
    ---For chart use (via view="gauss" attribute), generate() is called directly.
    ---@param code table Pandoc Code element
    ---@param ctx Context
    ---@return table|nil Replacement inlines
    on_render_Code = function(code, ctx)
        local rest = match_gauss_code(code.text or "")
        if rest == nil then return nil end

        local params = parse_params(rest)

        if not pandoc then
            return nil
        end

        -- For inline rendering, show the parameters
        local mean = params.mean or 0
        local sigma = params.sigma or 1
        local text = string.format("N(%.2g, %.2g)", mean, sigma)

        return { pandoc.Str(text) }
    end
}

return M
