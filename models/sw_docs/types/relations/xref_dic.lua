---Cross-reference relation type for dictionary entries.
---Targets: DIC object type.
---
---@module xref_dic

return {
    kind = "relation",
    schema = {
        id = "XREF_DIC",
        extends = "LABEL_REF",
        long_name = "Dictionary Reference",
        description = "Cross-reference to a dictionary entry",
        target_type_ref = "DIC",
    },
    hooks = {
        -- Render dictionary refs as the entry's title alone (the prose context
        -- already implies "this is a term"; the PID would be noise).
        render_link = function(ctx)
            local target = ctx.subject.target
            if target.title and target.title ~= "" then
                return target.title
            end
        end,
    },
}
