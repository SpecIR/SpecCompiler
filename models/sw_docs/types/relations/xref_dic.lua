---Cross-reference relation type for dictionary entries.
---Targets: DIC object type.
---
---@module xref_dic

local link_rewrite = require("pipeline.shared.link_rewrite_utils")

local M = {}

M.relation = {
    id = "XREF_DIC",
    extends = "PID_REF",
    long_name = "Dictionary Reference",
    description = "Cross-reference to a dictionary entry",
    target_type_ref = "DIC",
}

M.handler = {
    name = "xref_dic_handler",
    prerequisites = {"spec_relations"},

    on_transform = function(data, contexts, _diagnostics)
        link_rewrite.rewrite_display_for_type(data, contexts, "XREF_DIC", function(target)
            if target.title_text and target.title_text ~= "" then
                return target.title_text
            end
        end)
    end
}

return M
