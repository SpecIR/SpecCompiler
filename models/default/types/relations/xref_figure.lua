---Cross-reference relation type for figures.
---Targets: FIGURE, PLANTUML, CHART float types.
---
---@module xref_figure

return {
    kind = "relation",
    schema = {
        id = "XREF_FIGURE",
        extends = "LABEL_REF",
        long_name = "Figure Reference",
        description = "Cross-reference to a figure",
        -- CHART is provided by overlay models (e.g. abnt); harmless/unmatched in a pure-default build.
        target_type_ref = "FIGURE,PLANTUML,CHART",
    },
}
