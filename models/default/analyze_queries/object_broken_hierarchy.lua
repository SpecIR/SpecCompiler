local SQL = require("models.default.analyze_queries.sql")

return {
    kind = "analyze",
    schema = {
        id = "object_broken_hierarchy",
        view = "view_object_broken_hierarchy",
        policy_key = "object_broken_hierarchy",
        sql = SQL.view_object_broken_hierarchy,
    },
    hooks = {
        message = function(ctx)
            local row = ctx.subject.row
            local title = row.title_text or "(untitled)"
            if row.defect == "empty_title" then
                return string.format(
                    "Broken heading hierarchy: a level %d heading has no title and would render as an "
                    .. "empty numbered heading, corrupting downstream numbering. Give it a title, or — to "
                    .. "close the current section without a heading — use a `----` thematic break instead "
                    .. "of an empty heading.",
                    row.level)
            end
            if row.defect == "orphan_root" then
                return string.format(
                    "Broken heading hierarchy: the document opens with '%s' at heading level %d, "
                    .. "but a shallower level %d heading appears later — the opening heading is "
                    .. "orphaned above its parent level. The first heading must be at the document's top level.",
                    title, row.level, row.context_level)
            end
            -- skipped_level
            return string.format(
                "Broken heading hierarchy: '%s' is a level %d heading immediately after a level %d heading ('%s'), "
                .. "skipping level %d. A heading may be at most one level deeper than the preceding heading.",
                title, row.level, row.context_level,
                row.context_title or "(untitled)", row.context_level + 1)
        end,
    },
}
