---SW Docs view definitions for sidebar navigation.
---Overrides the default views with domain-specific entries (coverage report).
---@module models.sw_docs.html.views_config
return {
    { name = "traceability", label = "Traceability Matrix" },
    { name = "coverage",     label = "Coverage Report" },
    { name = "dangling",     label = "Dangling References" },
    { name = "inventory",    label = "Float Inventory" },
    { name = "summary",      label = "Object Summary" },
}
