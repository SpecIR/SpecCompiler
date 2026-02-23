---Sidebar template.
---Generates the sidebar structure with doc selector and TOC placeholder.
---@module models.default.html.templates.sidebar
local M = {}

---Render the sidebar.
---@return string Sidebar HTML
function M.render()
    local parts = {
        '<aside class="sidebar">',
        '  <div class="sidebar-top">',
        '    <div id="doc-selector"></div>',
        '  </div>',
        '  <div class="sidebar-scroll" id="sidebar-scroll">',
        '    <div id="sidebar-search-results" class="sidebar-search-results" style="display:none"></div>',
        '    <nav id="sidebar-toc" class="sidebar-toc"></nav>',
    }
    parts[#parts + 1] = '  </div>'
    parts[#parts + 1] = '</aside>'

    return table.concat(parts, '\n')
end

return M
