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
        -- Render dictionary refs as glossary-like inline terms. Dictionary
        -- entries are often shared by SRS/SDD/SVC documents, so suppress the
        -- generic cross-spec prefix: the prose needs the term, not its source.
        render_link = function(ctx)
            local target = ctx.subject.target
            if target.title and target.title ~= "" then
                return {
                    text = "<" .. target.title .. ">",
                    suppress_spec_prefix = true,
                }
            end
        end,
    },
}
