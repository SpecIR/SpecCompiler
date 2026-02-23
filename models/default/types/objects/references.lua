---References object type for the default model.
---An unnumbered section for bibliography / references.
---
---Usage:
---  ## REFERENCES: References
---  Bibliography entries follow...

local spec_object_base = require("pipeline.shared.spec_object_base")

local M = {}

M.object = {
    id = "REFERENCES",
    long_name = "References",
    description = "Bibliography / references section",
    is_composite = true,
    numbered = false,
    implicit_aliases = { "references", "bibliography", "works cited" },
}

M.handler = spec_object_base.create_handler("references_handler", {
    unnumbered = true,
    skip_attributes = true,
})

return M
