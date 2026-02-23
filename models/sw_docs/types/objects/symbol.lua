---Symbol type module for code symbols extracted from firmware analysis.

local M = {}

M.object = {
    id = "SYMBOL",
    long_name = "Code Symbol",
    description = "A code symbol (function, variable, register) extracted from firmware analysis",
    pid_prefix = "SYMBOL",
    pid_format = "%s-%s",  -- SYM-{name}
    attributes = {
        { name = "kind", type = "STRING" },        -- function, register, variable, etc.
        { name = "source", type = "STRING" },      -- Source file and line location
        { name = "complexity", type = "INT" },     -- Cyclomatic complexity (for functions)
        { name = "calls", type = "STRING" },       -- Comma-separated list of called functions
    }
}

return M
