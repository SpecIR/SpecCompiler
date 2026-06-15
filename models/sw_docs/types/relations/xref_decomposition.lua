---Cross-reference relation type for software decomposition entries.
---Targets: CSC and CSU object types (MIL-STD-498 decomposition).
---
---@module xref_decomposition

return {
    kind = "relation",
    schema = {
        id = "XREF_DECOMPOSITION",
        extends = "LABEL_REF",
        long_name = "Decomposition Reference",
        description = "Cross-reference to a software decomposition element (CSC or CSU)",
        target_type_ref = "CSC,CSU",
    },
    hooks = {
        -- Render decomposition refs as "<TYPE> <title>" (e.g. "CSC Authentication")
        -- so the code identifier stays visible next to the human-readable title.
        render_link = function(ctx)
            local target = ctx.subject.target
            if target.title and target.title ~= "" then
                return target.type_ref .. " " .. target.title
            end
        end,
    },
}
