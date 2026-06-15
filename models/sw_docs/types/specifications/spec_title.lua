---SPEC_TITLE base specification type.
---Carries the standard document-title render (a styled Title Div). Concrete
---specification types (SRS, SDD, SVC, SUM, TRR) extend this and inherit the
---title via the host's extends-chain dispatch; they declare render options
---(show_pid, style) as plain schema fields. The default SPEC type does NOT
---extend SPEC_TITLE, so untyped H1 documents render no title Div.
---
---@module spec_title
local specification_base = require("pipeline.shared.specification_base")

return {
    kind = "specification",
    schema = {
        id = "SPEC_TITLE",
        long_name = "Titled Specification",
        description = "Base type for specifications that render a document title",
        extends = "SPEC",
    },
    hooks = { render = specification_base.title_render },
}
