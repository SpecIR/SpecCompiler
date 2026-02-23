---Content area template.
---Generates document section wrappers.
---@module models.default.html.templates.content
local M = {}

---Wrap a document's body HTML in a section element.
---@param spec_id string Specification identifier (e.g., "srs", "sdd")
---@param body_html string Pandoc-generated HTML body content
---@param is_first boolean Whether this is the first (default active) document
---@return string Section HTML
function M.render_section(spec_id, body_html, is_first)
    return string.format(
        '<section id="doc-%s" class="doc-section%s">%s</section>',
        spec_id,
        is_first and " active" or "",
        body_html
    )
end

return M
