---Traces To relation module for SpecCompiler.

local M = {}

M.relation = {
    id = "TRACES_TO",
    extends = "PID_REF",
    long_name = "Traces To",
    description = "Traceability link from one object to another",
}

return M
