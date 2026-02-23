---Cross-reference relation type for software decomposition entries.
---Targets: CSC and CSU object types (MIL-STD-498 decomposition).
---
---@module xref_decomposition

local link_rewrite = require("pipeline.shared.link_rewrite_utils")

local M = {}

M.relation = {
    id = "XREF_DECOMPOSITION",
    extends = "LABEL_REF",
    long_name = "Decomposition Reference",
    description = "Cross-reference to a software decomposition element (CSC or CSU)",
    target_type_ref = "CSC,CSU",
}

M.handler = {
    name = "xref_decomposition_handler",
    prerequisites = {"spec_relations"},

    on_transform = function(data, contexts, _diagnostics)
        link_rewrite.rewrite_display_for_type(data, contexts, "XREF_DECOMPOSITION", function(target)
            if target.title_text and target.title_text ~= "" then
                return target.type_ref .. " " .. target.title_text
            end
        end)
    end
}

return M
