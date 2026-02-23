---Cross-reference relation type for figures.
---Targets: FIGURE, PLANTUML, CHART float types.
---
---@module xref_figure

local M = {}

M.relation = {
    id = "XREF_FIGURE",
    extends = "LABEL_REF",
    long_name = "Figure Reference",
    description = "Cross-reference to a figure",
    target_type_ref = "FIGURE,PLANTUML,CHART",
}

return M
